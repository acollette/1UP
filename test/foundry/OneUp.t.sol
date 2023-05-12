// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

//standard test libs
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

// import OZ lib
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//import contract to test
import "../../contracts/OneUp.sol";

contract Test_OneUP {

    using SafeERC20 for IERC20;

    OneUp OneUpContract;

    function setup() public {
        OneUpContract = new OneUp();

        
    }


}