// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


////////// Interfaces //////////

interface ISt1inch {
    function deposit(uint256 amount, uint256 duration) external;
    function withdraw() external;
}

interface IPowerPod {
    function delegate(address delegatee) external;
}

interface IMultiFarmingPod {
    function claim() external;
}

interface IBalancerPoolCreationHelper {
    function initJoinStableSwap(
        bytes32 poolId,
        address poolAddress,
        address[] memory tokenAddresses,
        uint256[] memory weiAmountsPerToken
    ) external;
}

interface IBalancerPool {
    function getPoolId() external view returns(bytes32);
    function getActualSupply() external view returns (uint256);
}

interface IBalancerVault {
    function getPoolTokens(bytes32) external view returns (address[] memory, uint256[] memory, uint256);
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;
    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external payable;
}

struct JoinPoolRequest {
    address[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

struct ExitPoolRequest {
    address[] assets;
    uint256[] minAmountsOut;
    bytes userData;
    bool toInternalBalance;
}



////////// Contract //////////

contract OneUp is ERC4626 {

    using SafeERC20 for IERC20;

    ////////// State Variables //////////

    IERC20 immutable public oneInchToken = IERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    address immutable public stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;  
    address immutable public powerPod = 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947;
    address immutable public resolverFarmingPod = 0x7E78A8337194C06314300D030D41Eb31ed299c39;
    address immutable public balancerPoolCreationHelper = 0xa289a03f46f144fAaDd9Fc51b006d7322ECc9B04;
    address immutable public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    bool public vaultStarted;               /// @dev Will be set to "true" after first deposit 
    bool public poolAddressSet;             /// @dev Returns "true" once the Balancer Pool address has been set
    bool public poolInitialized;            /// @dev Returns "true" once initial liquidity has been provided to the pool
    bool public poolEnded;                  /// @dev Pool ends when all 1inch tokens are unstaked after duration period
    address public delegatee;               /// @dev The address of the current delegatee
    address public balancerPool;            /// @dev The 1inch/1UP Curve Pool
    uint256 public endTime;                 /// @dev The time at which the vault balance will be unstakable
    uint256 public lastUpdateEndTime;       /// @dev The last time that "endTime" was updated
    uint256 public totalStaked;             /// @dev Keeps track of total 1Inch tokens staked in this 
    uint256 public poolInitialDeposit1UP;   /// @dev First 1UP deposited in pool in order to avoid double accounting

    

    ////////// Constructor //////////

    constructor() ERC4626(oneInchToken) ERC20("oneUP", "1UP") {

    }



    ////////// Functions //////////

    /// @notice Will calculate total holding of asset of this pool
    function totalAssets() public view override returns (uint256) {
        if (poolInitialized == true && poolEnded == false) {
            (, uint256[] memory balances,) 
            = IBalancerVault(balancerVault).getPoolTokens(IBalancerPool(balancerPool).getPoolId());

            uint256 contractPoolBalance = (IERC20(balancerPool).balanceOf(address(this)) * (balances[0] + balances[1])) /
            IBalancerPool(balancerPool).getActualSupply(); 

            return contractPoolBalance + totalStaked;    
        } else if (poolEnded == true) {
            return oneInchToken.balanceOf(address(this));
        } else {
            return totalStaked;
        }
    }

    /// @notice Deposits 1inch tokens in the vault, stakes 1inch, delegates UP and mints 1UP tokens / shares.
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");
        require(poolEnded = false, "Pool ended");

        uint256 duration;

        // We set the starting values for the duration as well as initial delegatee
        if (vaultStarted == false) {
            duration = 31556926; // 1 year
            delegatee = 0xA260f8b7c8F37C2f1bC11b04c19902829De6ac8A;
            endTime = block.timestamp + 31556926; // time at which vault balance will be unstakable
            lastUpdateEndTime = block.timestamp; 
        } else if (block.timestamp > lastUpdateEndTime + 30 days) {
            endTime += 30 days;
            lastUpdateEndTime = block.timestamp;
            duration = 30 days;
        }

        vaultStarted = true;

        uint256 shares = previewDeposit(assets);
        totalStaked += assets;
        _deposit(_msgSender(), receiver, assets, shares);

        // Stake tokens
        IERC20(address(oneInchToken)).safeApprove(stake1inch, assets);
        ISt1inch(stake1inch).deposit(assets, duration);

        // Delegate UP
        IPowerPod(powerPod).delegate(delegatee);

        return shares;
    }

    /// @notice This function will claim rewards from the delegates and provide liquidity in the Balancer pool.
    function claimRewardsFromDelegate() public {
        require(poolInitialized == true, "Make an initial deposit to the Balancer pool before claiming");
        IMultiFarmingPod(resolverFarmingPod).claim();
        
        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();
        uint256 toDeposit = IERC20(address(oneInchToken)).balanceOf(address(this));

        (address[] memory tokens,,) = 
        IBalancerVault(balancerVault).getPoolTokens(poolId);

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[0] = toDeposit;      
        maxAmountsIn[1] = 0;
        maxAmountsIn[2] = 0;

        uint256[] memory userDataAmounts = new uint256[](2);
        maxAmountsIn[0] = toDeposit;      
        maxAmountsIn[1] = 0;

        bytes memory userData = abi.encode(1, userDataAmounts, 0);

        JoinPoolRequest memory request;
        request.assets = tokens;
        request.maxAmountsIn = maxAmountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        IERC20(address(oneInchToken)).safeApprove(balancerVault, toDeposit);
        IBalancerVault(balancerVault).joinPool(poolId, address(this), address(this), request);
    }

    /// @notice Sets the Balancer 1inch/1UP pool address for this contract and initializes the pool with first deposit.
    function setBalancerPool(address _balancerPool) public {
        require(poolAddressSet == false, "Curve pool already set");

        poolAddressSet == true;
        balancerPool = _balancerPool;
    }

    /// @notice This function will initialize the Balancer pool by providing the first liquidity.
    function initBalancerPool(uint256[] memory amounts) public {
        require(poolInitialized == false, "Balancer pool already intialized");
        require(amounts[0] >= 1_000 ether && amounts[1] >= 1_000 ether, "insufficient amounts");

        poolInitialized = true;
        totalStaked -= amounts[1];

        IERC20(address(oneInchToken)).safeTransferFrom(_msgSender(), address(this), amounts[0]);
        IERC20(address(this)).safeTransferFrom(_msgSender(), address(this), amounts[1]);

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(oneInchToken);
        tokenAddresses[1] = address(this);

        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

        IERC20(address(oneInchToken)).safeApprove(balancerPoolCreationHelper, amounts[0]);
        IERC20(address(this)).safeApprove(balancerPoolCreationHelper, amounts[1]);

        IBalancerPoolCreationHelper(balancerPoolCreationHelper).initJoinStableSwap(
            poolId, 
            balancerPool, 
            tokenAddresses, 
            amounts
        );
    }

    /// @notice This function will unstake 1inch tokens after duration ends and remove liquidity from the Balancer pool.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");
        poolEnded = true;
        totalStaked = 0;

        // Will not be callable if we still have a staked duration
        ISt1inch(stake1inch).withdraw();

        // remove liquidity from BalancerPool
        (address[] memory tokens,,) 
        = IBalancerVault(balancerVault).getPoolTokens(IBalancerPool(balancerPool).getPoolId());
        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;
        minAmountsOut[2] = 0;

        bytes memory userData = abi.encode(1, IERC20(balancerPool).balanceOf(address(this)), 0);

        ExitPoolRequest memory request;
        request.assets = tokens;
        request.minAmountsOut = minAmountsOut;
        request.userData = userData;
        request.toInternalBalance = false;

        IBalancerVault(balancerVault).exitPool(poolId, address(this), address(this), request);

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

}
