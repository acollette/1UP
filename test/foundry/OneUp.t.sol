// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

//standard test libs
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

// import OZ lib
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//import contract to test
import {OneUp} from "../../contracts/OneUp.sol";

contract Test_OneUP is Test {

    using SafeERC20 for IERC20;

    address bob = 0x972eA38D8cEb5811b144AFccE5956a279E47ac46;
    address oneInchToken = 0x111111111117dC0aa78b770fA6A738034120C302;
    address stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;

    OneUp OneUpContract;

    function setUp() public {
        OneUpContract = new OneUp();

    }

    function test_OneUp_init_state() public {
        assert(address(OneUpContract.oneInchToken()) == 0x111111111117dC0aa78b770fA6A738034120C302);
        assert(OneUpContract.stake1inch() == 0x9A0C8Ff858d273f57072D714bca7411D717501D7);
        assert(OneUpContract.powerPod() == 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947);
        assert(OneUpContract.vaultStarted() == false);
    }

    function test_OneUp_deposit_state() public {
        
        uint256 amount = 100 ether;
        deal(address(OneUpContract.oneInchToken()), bob, amount);

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, bob);
        vm.stopPrank();

        emit log_named_uint("1UP token balance of Bob", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        vm.warp(block.timestamp + 100 days);

        emit log_named_uint("1inch staked tokens of vault after", IERC20(stake1inch).balanceOf(address(OneUpContract)));


    }



}