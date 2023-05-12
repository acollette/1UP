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

interface IStakingFarmingPod {
    function claim() external;
}

interface ICurveBasePool{
    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external;
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts) external;
}



    ////////// Contract //////////

contract OneUp is ERC4626 {

    using SafeERC20 for IERC20;

    ////////// State Variables //////////

    IERC20 immutable public oneInchToken = IERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    address immutable public stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;  
    address immutable public powerPod = 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947;
    address immutable public stakingFarmingPod = 0x1A87c0F9CCA2f0926A155640e8958a8A6B0260bE;
    address public curvePool;   /// @dev The 1inch/1UP Curve Pool

    bool public vaultStarted;   /// @dev Will be set to "true" after first deposit 
    bool public curvePoolSet;   /// @dev Returns "true" once the Curve Pool has been set
    address public delegatee;   /// @dev The address of the current delegatee
    uint256 public endTime;     /// @dev The time at which the vault balance will be unstakable
    uint256 public lastUpdateEndTime; /// @dev The last time that "endTime" was updated



    ////////// Constructor //////////

    constructor() ERC4626(oneInchToken) ERC20("oneUP", "1UP") {

    }



    ////////// Functions //////////

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 duration;

        // We set the starting values for the duration and first delegatee assigned
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

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        // Stake tokens
        IERC20(oneInchToken).safeApprove(stake1inch, assets);
        ISt1inch(stake1inch).deposit(assets, duration);

        // Delegate UP
        IPowerPod(powerPod).delegate(delegatee);

        return shares;
    }

    function claimRewardsFromDelegate() public {
        IStakingFarmingPod(stakingFarmingPod).claim();

    }

    function claimRewardsFromCurve() public {
        
    }
    
    function setCurvePool(address _curvePool) public {
        require(curvePoolSet == false, "Curve pool already set");

        curvePoolSet == true;
        curvePool = _curvePool;
    }
}
