// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


    ////////// Interfaces //////////

interface ISt1inch {
    function deposit(uint256 amount, uint256 duration) external;
}

interface IPowerPod {
    function delegate(address delegatee) external;
}

    ////////// Contract //////////

contract OneUp is ERC4626 {

    using SafeERC20 for IERC20;

    ////////// State Variables //////////

    IERC20 immutable oneInchToken = IERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    address immutable stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;  
    address immutable powerPod = 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947;
    
    bool public vaultStarted;   /// @dev Will be set to "true" after first deposit 
    address public delegatee;   /// @dev The address of the current delegatee


    ////////// Constructor //////////

    constructor() ERC4626(oneInchToken) ERC20("oneUP", "1UP") {

    }



    ////////// Functions //////////

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 duration;

        // We set the starting values for the duration and first delegatee assigned
        if (vaultStarted == false) {
            duration = 31556926;
            delegatee = 0xC6c7565644EA1893ad29182F7B6961AAb7EDFeD0;
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        // Stake tokens
        IERC20(oneInchToken).safeApprove(stake1inch, assets);
        ISt1inch(stake1inch).deposit(assets, duration);

        // Delegate UP
        IPowerPod(powerPod).delegate(delegatee);

        return shares;
    }
    

}
