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
    OneUpMultiRewards OneUpStakingContract;
   

    ///////////// Helper Functions //////////////

    function deposit(address user, uint256 amount, bool stake) public {
        deal(address(OneUpContract.oneInchToken()), user, amount);

        vm.startPrank(user);
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
        OneUpStakingContract = OneUpContract.stakingContract();

        assert(OneUpContract.firstDeposit() == true);
        assert(OneUpContract.endTime() == 0);

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
        deposit(bob, 1_000 ether, false);
        deal(oneInchToken, bob, 1_000 ether);

        // check after first deposit
        assert(OneUpContract.firstDeposit() == false);
        assert(OneUpContract.endTime() == block.timestamp + OneUpContract.duration());        

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

        assert(address(OneUpStakingContract.stakingToken()) == address(OneUpContract));

        assert(OneUpContract.firstDeposit() == false); // As first deposit has been made in setUp()
        assert(OneUpContract.vaultEnded() == false);
        assert(OneUpContract.delegatee() == 0xA260f8b7c8F37C2f1bC11b04c19902829De6ac8A);
        assert(OneUpContract.lastUpdateEndTime() == block.timestamp);
        assert(OneUpContract.duration() == 31556926);

        (address[] memory tokens, uint256[] memory balances,) = 
        IBalancerVault(balancerVault).getPoolTokens(IBalancerVault(balancerPool).getPoolId());

        emit log_array(tokens);
        emit log_array(balances);
        emit log_named_address("OneUpContract", address(OneUpContract));
        emit log_named_address("stakingContract", address(OneUpContract.stakingContract()));
    }

    function test_OneUpV2_depositAndStake_state() public {
        
        uint256 amount = 100 ether;
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        // pre check
        uint256 initStaked1InchBob = IERC20(stake1inch).balanceOf(address(OneUpContract));

        emit log_named_uint("1UP token balance of Bob init", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault init", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, true);
        vm.stopPrank();

        // check
        assert(IERC20(address(OneUpContract)).balanceOf(bob) == 0);
        assert(OneUpStakingContract.balanceOf(bob) == amount);
        assert(IERC20(stake1inch).balanceOf(address(OneUpContract)) > initStaked1InchBob);
    }

    function test_OneUpV2_depositNoStake_state() public {
        
        uint256 amount = 100 ether;
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        // pre check
        uint256 initStaked1UPBob = OneUpStakingContract.balanceOf(bob);
        uint256 initStaked1InchBob = IERC20(stake1inch).balanceOf(address(OneUpContract));
        assert(IERC20(address(OneUpContract)).balanceOf(bob) == 0);

        emit log_named_uint("1UP token balance of Bob init", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault init", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, false);
        vm.stopPrank();

        // check
        assert(IERC20(address(OneUpContract)).balanceOf(bob) == amount);
        assert(OneUpStakingContract.balanceOf(bob) == initStaked1UPBob);
        assert(IERC20(stake1inch).balanceOf(address(OneUpContract)) > initStaked1InchBob);
    }

    function test_depositAndExtendDuration_state() public {

        uint256 amount = 100 ether;
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        // pre check
        assert(OneUpContract.endTime() == block.timestamp + OneUpContract.duration());

        // we're warping over 31 days in order to adapt "endTime" of the vault
        vm.warp(block.timestamp + 31 days);

        deposit(bob, amount, false);

        // check
        assert(OneUpContract.endTime() == block.timestamp + OneUpContract.duration());
    }

    function test_OneUpV2_withdraw_vaultNotEnded_state() public {
        deposit(bob, 1_000 ether, false);
        assert(IERC20(oneInchToken).balanceOf(bob) == 0);
        assert(OneUpContract.balanceOf(bob) == 1_000 ether);
        assert(OneUpContract.vaultEnded() == false);

        vm.warp(OneUpContract.endTime() + 1);

        vm.startPrank(bob);
        OneUpContract.withdraw();
        vm.stopPrank();

        assert(OneUpContract.vaultEnded() == true);
        assert(IERC20(oneInchToken).balanceOf(bob) == 1_000 ether);
        assert(OneUpContract.balanceOf(bob) == 0);

    }

    function test_OneUpV2_withdraw_vaultEnded_state() public {
        deposit(bob, 1_000 ether, false);
        deposit(alice, 5_000 ether, false);
        assert(IERC20(oneInchToken).balanceOf(bob) == 0);
        assert(IERC20(oneInchToken).balanceOf(alice) == 0);
        assert(OneUpContract.balanceOf(bob) == 1_000 ether);
        assert(OneUpContract.balanceOf(alice) == 5_000 ether);

        assert(OneUpContract.vaultEnded() == false);

        vm.warp(OneUpContract.endTime() + 1);

        // first withdraw which will set "vaultEnded" to "true and unstake from 1inch staking contract
        vm.startPrank(bob);
        OneUpContract.withdraw();
        vm.stopPrank();

        assert(OneUpContract.vaultEnded() == true);
        assert(IERC20(oneInchToken).balanceOf(bob) == 1_000 ether);
        assert(OneUpContract.balanceOf(bob) == 0);

        // second withdraw which will skip unstaking from 1inch staking contract
        vm.startPrank(alice);
        OneUpContract.withdraw();
        vm.stopPrank();

        assert(OneUpContract.vaultEnded() == true);
        assert(IERC20(oneInchToken).balanceOf(alice) == 5_000 ether);
        assert(OneUpContract.balanceOf(alice) == 0);

    }

    function test_OneUpV2_AddRewardsAndGetReward_state() public {
        deposit(bob, 1_000 ether, true);

        vm.warp(block.timestamp + 10 days);

        // pre check
        assert(IERC20(oneInchToken).balanceOf(bob) == 0);

        // For now we will bypass claiming on the farming pod and simulate the rewards received
        deal(oneInchToken, address(OneUpContract), 2_000 ether);
        vm.startPrank(address(OneUpContract));
        IERC20(oneInchToken).safeApprove(address(OneUpStakingContract), 2_000 ether);
        OneUpStakingContract.notifyRewardAmount(oneInchToken, 2_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(bob);
        OneUpStakingContract.getReward();
        vm.stopPrank();

        assert(IERC20(oneInchToken).balanceOf(bob) > 0);
        emit log_named_uint("1inch claimed bob", IERC20(oneInchToken).balanceOf(bob));

    }

}
