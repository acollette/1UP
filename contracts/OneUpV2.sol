// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

interface IMultiRewards {
    function addReward(address, address, uint256) external;
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;
    function stake(uint256 amount) external;
    function stakeFor(uint256 amount, address account) external;
}



////////// Contract //////////

contract OneUpV2 is ERC20 {

    using SafeERC20 for IERC20;

    ////////// State Variables //////////

    IERC20 immutable public oneInchToken = IERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    address immutable public stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;  
    address immutable public powerPod = 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947;
    address immutable public resolverFarmingPod = 0x7E78A8337194C06314300D030D41Eb31ed299c39;
    

    bool public vaultStarted;               /// @dev Will be set to "true" after first deposit 
    bool public vaultEnded;                 /// @dev Vault ends when all 1inch tokens are unstaked after duration period
    address public delegatee;               /// @dev The address of the current delegatee
    address public balancerPool;            /// @dev The 1inch/1UP Curve Pool
    address public stakingContract;
    uint256 public endTime;                 /// @dev The time at which the vault balance will be unstakable
    uint256 public lastUpdateEndTime;       /// @dev The last time that "endTime" was updated
    uint256 public totalStaked;             /// @dev Keeps track of total 1Inch tokens staked in this 
    uint256 public poolInitialDeposit1UP;   /// @dev First 1UP deposited in pool in order to avoid double accounting
    


    ////////// Constructor //////////

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        
    }



    ////////// Functions //////////

    /// @notice Deposits 1inch tokens in the vault, stakes 1inch, delegates UP and mints 1UP tokens / shares.
    /// @param amount The amount of assets to deposit.
    /// @param stake If "true" will automatically stake the ERC20 token to accumulate rewards.
    function deposit(uint256 amount, bool stake) public {
        require(vaultEnded == false, "Vault ended");

        uint256 duration;

        // We set the starting values for the duration as well as initial delegatee
        // TODO: transfer part of variables to constructor
        if (vaultStarted == false) {
            duration = 31556926; // 1 year
            delegatee = 0xA260f8b7c8F37C2f1bC11b04c19902829De6ac8A;
            endTime = block.timestamp + 31556926; // time at which vault balance will be unstakable
            lastUpdateEndTime = block.timestamp; 
            vaultStarted = true;
        } else if (block.timestamp > lastUpdateEndTime + 30 days) {
            endTime += 30 days;
            lastUpdateEndTime = block.timestamp;
            duration = 30 days;
        }

        // Deposit 1inch tokens
        oneInchToken.safeTransferFrom(_msgSender(), address(this), amount);

        // Mint 1UP tokens on 1:1 basis
        _mint(stake == true ? address(this) : _msgSender(), amount);

        // Stake tokens
        oneInchToken.safeApprove(stake1inch, amount);
        ISt1inch(stake1inch).deposit(amount, duration);

        // Stake for account in rewards contract
        if (stake == true) { IMultiRewards(stakingContract).stakeFor(amount, _msgSender()); }

        // Delegate UP
        IPowerPod(powerPod).delegate(delegatee);

    }

    /// @notice This function will claim rewards from the delegates and add the rewards to the staking contract
    /// TODO: when pool is closed not able to call fct anymore.
    /// TODO: add a earned fct to view rewards claimable
    function claimRewardsFromDelegate() public {
        IMultiFarmingPod(resolverFarmingPod).claim();
        uint256 toDeposit = oneInchToken.balanceOf(address(this));
        oneInchToken.safeApprove(stakingContract, toDeposit);
        IMultiRewards(stakingContract).notifyRewardAmount(address(oneInchToken), toDeposit);
    }



    /// @notice This function will unstake 1inch tokens after duration ends and remove liquidity from the Balancer pool.
    function withdraw() external {
        require(block.timestamp > endTime, "pool not ended");

        uint256 amountWithdrawable;
        
        if (vaultEnded == false) {
            // Will not be callable if we still have a staked duration
            ISt1inch(stake1inch).withdraw();
            amountWithdrawable = balanceOf(_msgSender());
            _burn(_msgSender(), balanceOf(_msgSender()));
            oneInchToken.safeTransfer(_msgSender(), amountWithdrawable);

            vaultEnded = true;

        } else {
            amountWithdrawable = balanceOf(_msgSender());
            _burn(_msgSender(), balanceOf(_msgSender()));
            oneInchToken.safeTransfer(_msgSender(), amountWithdrawable);
        }
    }
}
