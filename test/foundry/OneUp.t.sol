// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

//standard test libs
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

// import OZ lib
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//import contract to test
import {OneUp} from "../../contracts/OneUp.sol";

interface ICurveFactory {
    function deploy_plain_pool(
        string memory _name, 
        string memory _symbol, 
        address[4] memory _coins, 
        uint256 _A, 
        uint256 _fee, 
        uint256 _asset_type, 
        uint256 _implementation_idx
    ) external returns (address);
}

contract Test_OneUP is Test {

    using SafeERC20 for IERC20;

    address bob = 0x972eA38D8cEb5811b144AFccE5956a279E47ac46;
    address oneInchToken = 0x111111111117dC0aa78b770fA6A738034120C302;
    address stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;
    address curveFactory = 0xB9fC157394Af804a3578134A6585C0dc9cc990d4;

    OneUp OneUpContract;

    function setUp() public {
        OneUpContract = new OneUp();

        // deploy Curve Pool for 1inch/1UP tokens
        string memory _name = "1inch/1UP";
        string memory _symbol = "1inch-1UP";
        address[4] memory _coins = [oneInchToken, address(OneUpContract), address(0x0), address(0x0)];
        uint256 _A = 300;
        uint256 _fee = 50000000; // 0.5 %

        address deployedCurvePool = ICurveFactory(curveFactory).deploy_plain_pool(_name, _symbol, _coins, _A, _fee, 3, 3); 
        
        emit log_named_address("Curve Pool deployed", deployedCurvePool);
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

        // pre check
        assert(IERC20(address(OneUpContract)).balanceOf(bob) == 0);
        assert(IERC20(stake1inch).balanceOf(address(OneUpContract)) == 0);

        emit log_named_uint("1UP token balance of Bob init", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault init", IERC20(stake1inch).balanceOf(address(OneUpContract)));

        vm.startPrank(bob);
        IERC20(oneInchToken).safeApprove(address(OneUpContract), amount);
        OneUpContract.deposit(amount, bob);
        vm.stopPrank();

        // check
        assert(IERC20(address(OneUpContract)).balanceOf(bob) > 0);
        assert(IERC20(stake1inch).balanceOf(address(OneUpContract)) > 0);
        assert(OneUpContract.endTime() == block.timestamp + 31556926);
        assert(OneUpContract.lastUpdateEndTime() == block.timestamp);

        emit log_named_uint("1UP token balance of Bob after", IERC20(address(OneUpContract)).balanceOf(bob));
        emit log_named_uint("1inch staked tokens of vault after", IERC20(stake1inch).balanceOf(address(OneUpContract)));
        
    }

    function test_OneUp_claimRewardsFromDelegates_state() public {


    }



}