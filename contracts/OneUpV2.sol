// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OneUpMultiRewards} from "../contracts/OneUpRewards.sol";

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
    function rewardsTokens() external view returns (address[] memory);
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
    OneUpMultiRewards public stakingContract; /// @dev The address of the staking contract where all rewards from 1inch staking will be sent

    address immutable public stake1inch = 0x9A0C8Ff858d273f57072D714bca7411D717501D7;  
    address immutable public powerPod = 0xAccfAc2339e16DC80c50d2fa81b5c2B049B4f947;
    address immutable public resolverFarmingPod = 0x7E78A8337194C06314300D030D41Eb31ed299c39;

    bool public firstDeposit = true;        /// @dev Returns "false" after the first deposit has been made
    bool public vaultEnded;                 /// @dev Vault ends when all 1inch tokens are unstaked after duration period
    address public delegatee;               /// @dev The address of the current delegatee
    address[] rewardTokens;                 /// @dev Tokens given as reward from the resolver
    uint256 public endTime;                 /// @dev The time at which the vault balance will be unstakable
    uint256 public lastUpdateEndTime;       /// @dev The last time that "endTime" was updated
    uint256 public duration;                /// @dev Staking duration in Unix
    


    ////////// Constructor //////////

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _duration,
        address _delegatee
    ) 
        ERC20(_name, _symbol)
    {
        duration = _duration;
        delegatee = _delegatee;
        lastUpdateEndTime = block.timestamp; 
        stakingContract = new OneUpMultiRewards(address(this));
        stakingContract.addReward(address(oneInchToken), address(this), 14 days);
    }



    ////////// Functions //////////
    
    /// @notice Deposits 1inch tokens in the vault, stakes 1inch, delegates UP and mints 1UP tokens / shares.
    /// @param amount The amount of assets to deposit.
    /// @param stake If "true" will automatically stake the ERC20 token to accumulate rewards.
    /// TODO: What if first deposit done after 30 days ?
    function deposit(uint256 amount, bool stake) public {
        require(vaultEnded == false, "Vault ended");

        uint256 durationExtension;

        if (firstDeposit == true) {
            durationExtension = duration;
            endTime = block.timestamp + duration;
            firstDeposit = false;
        }

        if (block.timestamp > lastUpdateEndTime + 30 days) {
            endTime = block.timestamp + duration;
            durationExtension = block.timestamp - lastUpdateEndTime;
            lastUpdateEndTime = block.timestamp;
        }

        // Deposit 1inch tokens
        oneInchToken.safeTransferFrom(_msgSender(), address(this), amount);

        // Mint 1UP tokens on 1:1 basis
        _mint(stake == true ? address(this) : _msgSender(), amount);

        // Stake tokens
        oneInchToken.safeApprove(stake1inch, amount);
        ISt1inch(stake1inch).deposit(amount, durationExtension);

        // Stake for account in rewards contract
        if (stake == true) { 
            IERC20(address(this)).safeApprove(address(stakingContract), amount);
            IMultiRewards(address(stakingContract)).stakeFor(amount, _msgSender());
        }

        // Delegate UP
        IPowerPod(powerPod).delegate(delegatee);

    }

    /// @notice This function will claim rewards from the delegates and add the rewards to the staking contract
    function claimRewardsFromDelegate() public {
        updateRewardTokens();
        IMultiFarmingPod(resolverFarmingPod).claim();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (IERC20(rewardTokens[i]).balanceOf(address(this)) > 0) {
                uint256 toDeposit = IERC20(rewardTokens[i]).balanceOf(address(this));
                IERC20(rewardTokens[i]).safeApprove(address(stakingContract), toDeposit);
                IMultiRewards(address(stakingContract)).notifyRewardAmount(rewardTokens[i], toDeposit);
            }
        }
    }

    function updateRewardTokens() private {
        rewardTokens = IMultiFarmingPod(resolverFarmingPod).rewardsTokens();
        
    }

    /// @notice This function will unstake 1inch tokens after duration ends.
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
