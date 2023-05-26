// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

//standard test libs
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

// import OZ lib
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//import contract to test
import {OneUpV2} from "../../contracts/OneUpV2.sol";
import {OneUpMultiRewards} from "../../contracts/OneUpRewards.sol";

interface IComposableStablePool {
    function create(
        string memory name,
        string memory symbol, 
        address[] memory tokens, //
        uint256 amplificationParameter,
        address[] memory rateProviders, //  
        uint256[] memory tokenRateCacheDurations,
        bool[] memory exemptFromYieldProtocolFeeFlags,
        uint256 swapFeePercentage,
        address owner,
        bytes32 salt
    ) external returns (address);
}

interface IBalancerVault {
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;
    function getPoolId() external returns (bytes32);
    function getPoolTokens(bytes32) external returns (address[] memory, uint256[] memory, uint256);
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256);
}

interface IBalancerPool {
    function getActualSupply() external returns (uint256);
    function getPoolId() external view returns(bytes32);
}

interface IMultiFarmingPod {
    function startFarming(IERC20, uint256 amount, uint256 period) external;
    function claim() external;
    function farmed(IERC20 rewardsToken, address account) external returns(uint256);
}

interface IBalancerPoolCreationHelper {
    function initJoinStableSwap(
        bytes32 poolId,
        address poolAddress,
        address[] memory tokenAddresses,
        uint256[] memory weiAmountsPerToken
    ) external;
}

struct JoinPoolRequest {
    address[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

struct SingleSwap {
   bytes32 poolId;
   SwapKind kind;
   address assetIn;
   address assetOut;
   uint256 amount;
   bytes userData;
}

struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}

enum SwapKind { GIVEN_IN, GIVEN_OUT }


contract Test_OneUpV2 is Test {

    using SafeERC20 for IERC20;

    // users
    address bob = 0x972eA38D8cEb5811b144AFccE5956a279E47ac46;
    address alice = 0x5a29280d4668622ae19B8bd0bacE271F11Ac89dA;
    address nico = 0x1F7673Af4859f0ACD66bB01eda90a2694Ed271DB;

    address oneInchToken = 0x111111111117dC0aa78b770fA6A738034120C302;
    address stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;
    address balancerFactory = 0xfADa0f4547AB2de89D1304A668C39B3E09Aa7c76;
    address balancerPoolCreationHelper = 0xa289a03f46f144fAaDd9Fc51b006d7322ECc9B04;
    address balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address balancerPool;

    OneUpV2 OneUpContract;
    OneUpMultiRewards OneUpStaking;

    ///////////// Helper Functions //////////////

    function deposit(uint256 amount, bool stake) public {
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, stake);
        vm.stopPrank();
    } 

    function toBytes(address a) public pure returns (bytes memory b){
        assembly {
            let m := mload(0x40)
            a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
        }
    }

    function getPool1UPBalance() public returns (uint256 pool1UPBalance) {
        (, uint256[] memory balances,) = 
        IBalancerVault(balancerVault).getPoolTokens(IBalancerVault(balancerPool).getPoolId());

        return balances[1];
    }

    function getPool1InchBalance() public returns (uint256 pool1InchBalance) {
        (, uint256[] memory balances,) = 
        IBalancerVault(balancerVault).getPoolTokens(IBalancerVault(balancerPool).getPoolId());

        return balances[0];
    }

    function getPoolBPTBalance() public returns (uint256 poolBPTBalance) {
        (, uint256[] memory balances,) = 
        IBalancerVault(balancerVault).getPoolTokens(IBalancerVault(balancerPool).getPoolId());

        return balances[2];
    }



    ///////////// setUp //////////////

    function setUp() public {
        // Declare contract instances
        OneUpContract = new OneUpV2("OneUp", "1UP", 31556926, 0xA260f8b7c8F37C2f1bC11b04c19902829De6ac8A);
        OneUpStaking = new OneUpMultiRewards(address(OneUpContract));

        assert(OneUpContract.firstDeposit() == true);

        // deploy Balancer Pool for 1inch/1UP tokens
        string memory name = "1Inch/1UP";
        string memory symbol = "1inch-1UP";
        address[] memory tokens = new address[](2); //
        tokens[0] = oneInchToken;
        tokens[1] = address(OneUpContract);
        uint256 amplificationParameter = 30;
        address[] memory rateProviders = new address[](2); //
        rateProviders[0] = address(0x0);
        rateProviders[1] = address(0x0);
        uint256[] memory tokenRateCacheDurations = new uint256[](2); //
        tokenRateCacheDurations[0] = 0;
        tokenRateCacheDurations[1] = 0;
        bool[] memory exemptFromYieldProtocolFeeFlags = new bool[](2); //
        exemptFromYieldProtocolFeeFlags[0] = false;
        exemptFromYieldProtocolFeeFlags[1] = false;
        uint256 swapFeePercentage = 2000000000000000;
        address owner = bob;
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000000;


        balancerPool = IComposableStablePool(balancerFactory).create(
            name,
            symbol,
            tokens, 
            amplificationParameter, 
            rateProviders, 
            tokenRateCacheDurations, 
            exemptFromYieldProtocolFeeFlags,
            swapFeePercentage,
            owner,
            salt
        );

        // Send initial liquidity to balancer pool
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[0] = 1_000 ether;
        initAmounts[1] = 1_000 ether;

        // put initial balance of both tokens in bob wallet
        deposit(1_000 ether, false);
        deal(oneInchToken, bob, 1_000 ether);

        // call setBalancerPoolAndInit => Will supply first liquidity to the pool
        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(balancerPool, 1_000 ether);
        IERC20(address(OneUpContract)).safeApprove(balancerPool, 1_000 ether);

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(oneInchToken);
        tokenAddresses[1] = address(OneUpContract);

        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

        IERC20(oneInchToken).safeApprove(balancerPoolCreationHelper, initAmounts[0]);
        IERC20(address(OneUpContract)).safeApprove(balancerPoolCreationHelper, initAmounts[1]);

        IBalancerPoolCreationHelper(balancerPoolCreationHelper).initJoinStableSwap(
            poolId, 
            balancerPool, 
            tokenAddresses, 
            initAmounts
        );

        vm.stopPrank();

        emit log_named_bytes32("poolID", IBalancerVault(balancerPool).getPoolId());
        emit log_named_address("Balancer Pool deployed", balancerPool);

    }



    ///////////// Testing //////////////

    function test_OneUpV2_init_state() public {
        assert(address(OneUpContract.oneInchToken()) == 0x111111111117dC0aa78b770fA6A738034120C302);
        assert(OneUpContract.stake1inch() == 0x9A0C8Ff858d273f57072D714bca7411D717501D7);
        assert(OneUpContract.powerPod() == 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947);
        assert(OneUpContract.resolverFarmingPod() == 0x7E78A8337194C06314300D030D41Eb31ed299c39);

        assert(address(OneUpStaking.stakingToken()) == address(OneUpContract));

        assert(OneUpContract.firstDeposit() == false); // As first deposit has been made in setUp()
        assert(OneUpContract.vaultEnded() == false);
        assert(OneUpContract.delegatee() == 0xA260f8b7c8F37C2f1bC11b04c19902829De6ac8A);
        assert(OneUpContract.endTime() == block.timestamp + OneUpContract.duration());
        assert(OneUpContract.lastUpdateEndTime() == block.timestamp);
        assert(OneUpContract.duration() == 31556926);

        (address[] memory tokens, uint256[] memory balances,) = 
        IBalancerVault(balancerVault).getPoolTokens(IBalancerVault(balancerPool).getPoolId());

        emit log_array(tokens);
        emit log_array(balances);
        emit log_named_address("OneUpContract", address(OneUpContract));
        emit log_named_address("stakingContract", OneUpContract.stakingContract());
    }

/*     function test_OneUpV2_deposit_state() public {
        
        uint256 amount = 100 ether;
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        // pre check
        uint256 initBalanceBob1UP = IERC20(address(OneUpContract)).balanceOf(bob);
        uint256 initStaked1InchBob = IERC20(stake1inch).balanceOf(address(OneUpContract));

        emit log_named_uint("1UP token balance of Bob init", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault init", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, bob);
        vm.stopPrank();

        // check
        assert(IERC20(address(OneUpContract)).balanceOf(bob) > initBalanceBob1UP);
        assert(IERC20(stake1inch).balanceOf(address(OneUpContract)) > initStaked1InchBob);
        assert(OneUpContract.endTime() == block.timestamp + 31556926);
        assert(OneUpContract.lastUpdateEndTime() == block.timestamp);

        emit log_named_uint("1UP token balance of Bob after", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault after", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        uint256 balancerLPBalance = IERC20(balancerPool).balanceOf(address(OneUpContract));

        emit log_named_uint("balancerLPBalance", balancerLPBalance);
        
    }

    function test_OneUpV2_claimRewardsFromDelegates_state() public {
        uint256 amountToDeposit = 1_000 ether;
        uint256 daysToClaim = 100 days;

        deal(address(OneUpContract.oneInchToken()), bob, amountToDeposit);

        // make a deposit
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amountToDeposit);
        OneUpContract.deposit(amountToDeposit, bob);
        vm.stopPrank();
        
        // impersonate the distributor of the farm and start reward period
        address distributor = 0x5E89f8d81C74E311458277EA1Be3d3247c7cd7D1;
        address farmingPod = 0x7E78A8337194C06314300D030D41Eb31ed299c39;
        vm.startPrank(distributor);

        //emit log_named_uint("1inch balance farmingPod before", IERC20(oneInchToken).balanceOf(farmingPod));
        //IERC20(oneInchToken).safeApprove(farmingPod, 1_000_000 ether);
        //IMultiFarmingPod(farmingPod).startFarming(IERC20(oneInchToken), 1_000_000 ether, 60 days);
        //vm.stopPrank();
        //emit log_named_uint("1inch balance farmingPod after", IERC20(oneInchToken).balanceOf(farmingPod));

        // + 100 days
        vm.warp(block.timestamp + daysToClaim);

        // claim rewards
        //vm.startPrank(address(OneUpContract));
        //IMultiFarmingPod(farmingPod).claim();
        //vm.stopPrank();

        // simulate claiming rewards
        uint256 APROnPeriod = (daysToClaim * APR) / 365 days;
        uint256 amountClaimable = (APROnPeriod * amountToDeposit) / BIPS; 
        emit log_named_uint("Amount claimable", amountClaimable);
        simulateRewardsClaimed(amountClaimable);

    }

    function test_OneUpV2_fullFlow_simulation() public {
        emit log_named_uint("Alice 1UP init balance", OneUpContract.balanceOf(alice));
        emit log_named_uint("Nico 1UP init balance", OneUpContract.balanceOf(nico));
        emit log_named_uint("Balancer Pool init 1UP balance", getPool1UPBalance());

        emit log_named_uint("Alice 1Inch init balance", IERC20(oneInchToken).balanceOf(alice));
        emit log_named_uint("Nico 1Inch init balance", IERC20(oneInchToken).balanceOf(nico));
        emit log_named_uint("Balancer Pool init 1inch balance", getPool1InchBalance());

        vm.warp(block.timestamp + 10 days);

        ////////////// DAY 10 ///////////////
        emit log_string("********** Day 10 **********");
        emit log_string("Alice makes a deposit of 1_000 1Inch tokens");
        // Alice makes a deposit of 1_000 1Inch
        deal(oneInchToken, alice, 1_000 ether);

        vm.startPrank(alice);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), 1_000 ether);
        OneUpContract.deposit(1_000 ether, alice);
        vm.stopPrank();

        emit log_named_uint("Alice 1UP balance", OneUpContract.balanceOf(alice));
        emit log_named_uint("Balancer Pool 1UP balance", getPool1UPBalance());
        emit log_named_uint("Vault staked 1Inch balance", IERC20(stake1inch).balanceOf(address(OneUpContract)));
        emit log_named_uint("Balancer Pool 1inch balance", getPool1InchBalance());

        vm.warp(block.timestamp + 20 days);

        //////////// DAY 30 ///////////////////
        emit log_string("********** Day 30 **********");
        emit log_string("Nico makes a deposit of 200 1Inch tokens");
        // Bob makes a deposit of 200 1Inch
        deal(oneInchToken, nico, 200 ether);

        vm.startPrank(nico);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), 200 ether);
        OneUpContract.deposit(200 ether, nico);
        vm.stopPrank();

        emit log_named_uint("Alice 1UP balance", OneUpContract.balanceOf(alice));
        emit log_named_uint("Nico 1UP balance", OneUpContract.balanceOf(nico));
        emit log_named_uint("Balancer Pool 1UP balance", getPool1UPBalance());
        emit log_named_uint("Vault staked 1Inch balance", IERC20(stake1inch).balanceOf(address(OneUpContract)));
        emit log_named_uint("Balancer Pool 1inch balance", getPool1InchBalance());
        emit log_named_uint("OneUpContract BPT balance", IERC20(balancerPool).balanceOf(address(OneUpContract)));

        vm.warp(block.timestamp + 70 days);

        //////////// DAY 100 //////////////////////
        emit log_string("********** Day 100 **********");
        emit log_string("Vault will claim rewards for the first time");

        uint256 daysToClaim = 100 days;     // We know this is an approximation as we should do weighted average balance for simulation

        uint256 APROnPeriod = (daysToClaim * APR) / 365 days;
        uint256 amountClaimable = (APROnPeriod * OneUpContract.totalStaked()) / BIPS; 
        emit log_named_uint("Amount claimable", amountClaimable);
        simulateRewardsClaimed(amountClaimable);

        emit log_named_uint("Alice 1UP balance", OneUpContract.balanceOf(alice));
        emit log_named_uint("Nico 1UP balance", OneUpContract.balanceOf(nico));
        emit log_named_uint("Balancer Pool 1UP balance", getPool1UPBalance());
        emit log_named_uint("Vault staked 1Inch balance", IERC20(stake1inch).balanceOf(address(OneUpContract)));
        emit log_named_uint("Balancer Pool 1inch balance", getPool1InchBalance());
        emit log_named_uint("OneUpContract BPT balance", IERC20(balancerPool).balanceOf(address(OneUpContract)));
        
        vm.warp(block.timestamp + 10 days);
        //////////// DAY 110 //////////////////////
        emit log_string("********** Day 110 **********");
        emit log_string("Alice will get liquidity and swap 1UP for 1Inch in Balancer Pool");

        emit log_named_uint("Alice 1UP balance", OneUpContract.balanceOf(alice));
        SingleSwap memory ss;
        ss.poolId = IBalancerVault(balancerPool).getPoolId();
        ss.kind = SwapKind.GIVEN_IN;
        ss.assetIn = address(OneUpContract);
        ss.assetOut = oneInchToken;
        ss.amount = 5 ether;
        ss.userData = ""; 

        FundManagement memory fm;
        fm.sender = alice;
        fm.fromInternalBalance = false;
        fm.recipient = payable(alice);
        fm.toInternalBalance = false;

        vm.startPrank(alice);
        IERC20(address(OneUpContract)).safeApprove(balancerVault, 5 ether);
        IBalancerVault(balancerVault).swap(ss, fm, 0, block.timestamp);
        vm.stopPrank;
    } */

}
