// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "./helpers/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/SafeERC20.sol";

//solhint-disable not-rely-on-time
contract MultiRewardsStake is Ownable {
    using SafeERC20 for IERC20;

    // Base staking info
    IERC20 public stakingToken;
    RewardData private _data;
    
    // User reward info
    mapping(address => mapping (address => uint256)) private _userRewardPerTokenPaid;
    mapping(address => mapping (address => uint256)) private _rewards;

    // Reward token data
    uint256 private _totalRewardTokens;
    mapping (uint => RewardToken) private _rewardTokens;
    mapping (address => uint256) private _rewardTokenToIndex;

    // User deposit data
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // Store reward token data
    struct RewardToken {
        address token;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }

    // Store reward time data
    struct RewardData {
        uint64 periodFinish;
        uint64 rewardsDuration;
        uint64 lastUpdateTime;
    }

    constructor(
        address[] memory rewardTokens_,
        IERC20 stakingToken_
    ) {
        stakingToken = stakingToken_;
        _totalRewardTokens = rewardTokens_.length;

        for (uint i; i < rewardTokens_.length;) {
            _rewardTokens[i + 1].token = rewardTokens_[i];
            _rewardTokenToIndex[rewardTokens_[i]] = i + 1;
            unchecked { ++i; }
        }

        _data.rewardsDuration = 14 days;
    }

    /* VIEWS */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, _data.periodFinish);
    }

    function totalRewardTokens() external view returns (uint256) {
        return _totalRewardTokens;
    }

    // Get reward rate for all tokens
    function rewardPerToken() public view returns (uint256[] memory) {
        uint256 totalTokens = _totalRewardTokens;
        uint256 supply = _totalSupply;
        uint256[] memory tokens = new uint256[](totalTokens);
        if (supply == 0) {
            for (uint i = 0; i < totalTokens;) {
                tokens[i] = _rewardTokens[i + 1].rewardPerTokenStored;
                unchecked { ++i; }
            }
        } else {
            for (uint i = 0; i < totalTokens;) {
                RewardToken memory rewardToken = _rewardTokens[i + 1];
                uint256 timeAddition = lastTimeRewardApplicable() - _data.lastUpdateTime;
                uint256 rewardRate = rewardToken.rewardRate * 1e18 / supply;
                tokens[i] = rewardToken.rewardPerTokenStored + (
                    timeAddition * rewardRate
                );
                unchecked { ++i; }
            }
        }

        return tokens;
    }

    /**
     * @dev Get current rewards for one token
     * @param token the token address to lookup
     * @return rewardPerTokenStored the reward per token value
     */
    function rewardForToken(address token) external view returns (uint256) {
        uint256 index = _rewardTokenToIndex[token];
        uint256 supply = _totalSupply;

        if (supply == 0) {
            return _rewardTokens[index].rewardPerTokenStored;
        } else {
            RewardToken memory rewardToken = _rewardTokens[index];
            uint256 timeAddition = lastTimeRewardApplicable() - _data.lastUpdateTime;
            uint256 rewardRate = rewardToken.rewardRate * 1e18 / supply;
            return rewardToken.rewardPerTokenStored + (
                timeAddition * rewardRate
            );
        }
    }

    /**
     * @dev Calculate rewardPerTokenStored for a token
     * @param tokenIndex the index for the token
     * @return rewardPerTokenStored the reward per token value
     */
    function _rewardPerTokenStored(uint256 tokenIndex) private view returns (uint256)
    {
        uint256 supply = _totalSupply;

        if (supply == 0) {
            return _rewardTokens[tokenIndex].rewardPerTokenStored;
        } else {
            RewardToken memory rewardToken = _rewardTokens[tokenIndex];
            uint256 timeAddition = lastTimeRewardApplicable() - _data.lastUpdateTime;
            uint256 rewardRate = rewardToken.rewardRate * 1e18 / supply;

            return rewardToken.rewardPerTokenStored + (
                timeAddition * rewardRate
            );
        }
    }

    /**
     * @dev Get all reward tokens and data
     * @return rewardTokens an array of structs with all token data
     */
    function getRewardTokens() external view returns (RewardToken[] memory) {
        uint256 totalTokens = _totalRewardTokens;
        RewardToken[] memory tokens = new RewardToken[](totalTokens);
        for (uint i = 0; i < totalTokens;) {
            tokens[i] = _rewardTokens[i + 1];
            unchecked { ++i; }
        }

        return tokens;
    }

    /**
     * @dev Get account's unclaimed earnings
     * @param account the account to lookup
     * @return rewards an array of uint256 reward amounts
     */
    function earned(address account) external view returns (uint256[] memory) {
        uint256 totalTokens = _totalRewardTokens;
        uint256[] memory earnings = new uint256[](totalTokens);
        for (uint i = 0; i < totalTokens;) {
            earnings[i] = _earned(account, i + 1);
            unchecked { ++i; }
        }

        return earnings;
    }

    /**
     * @dev Get account's earnings for one token
     * @param account the account to lookup
     * @param tokenIndex the index of the reward token
     * @return reward the earned reward value
     */
    function _earned(address account, uint256 tokenIndex) private view returns (uint256)
    {
        address token = _rewardTokens[tokenIndex].token;
        uint256 reward = _rewardPerTokenStored(tokenIndex);
        return _balances[account] * (reward - _userRewardPerTokenPaid[account][token]) / 1e18 + _rewards[account][token];
    }

    /**
     * @dev Gets rewards for the entire reward duration
     * @return amounts an array of the total reward amounts
     */
    function getRewardForDuration() external view returns (uint256[] memory) {
        uint256 totalTokens = _totalRewardTokens;
        uint256[] memory currentRewards = new uint256[](totalTokens);
        for (uint i = 0; i < totalTokens;) {
            currentRewards[i] = _rewardTokens[i + 1].rewardRate * _data.rewardsDuration;
            unchecked { ++i; }
        }

        return currentRewards;
    }

    /* === MUTATIONS === */

    /**
     * @dev Stake tokens in contract
     * @param amount the amount to stake
     * @notice Calls updateReward modifier to update reward data
     */
    function stake(uint256 amount) external payable updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        uint256 currentBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBalance = stakingToken.balanceOf(address(this));
        uint256 supplyDiff = newBalance - currentBalance;
        _totalSupply = _totalSupply + supplyDiff;
        _balances[msg.sender] = _balances[msg.sender] + supplyDiff;
        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Withdraw staked tokens
     * @param amount the amount to withdraw
     * @notice Calls updateReward modifier to update reward data
     */
    function withdraw(uint256 amount) public payable updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Claims all outstanding rewards
     */
    function getReward() public payable {
        for (uint i = 0; i < _totalRewardTokens;) {
            _updateReward(msg.sender, i + 1);
            address token = _rewardTokens[i + 1].token;
            uint256 currentReward = _rewards[msg.sender][token];
            if (currentReward > 0) {
                _rewards[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, currentReward);
                emit RewardPaid(msg.sender, currentReward);
            }
            unchecked { ++i; }
        }

        _data.lastUpdateTime = uint64(lastTimeRewardApplicable());
    }

    /**
     * @dev Withdraws entire balance and claims rewards
     */
    function exit() external payable {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* === RESTRICTED FUNCTIONS === */

    /**
     * @dev Owner only function to deposit reward tokens
     * @param amounts array of reward amounts to deposit
     * @notice For all amounts over 0, owner must approve
     * token to be spent by contract prior to calling.
     */
    function depositRewardTokens(uint256[] memory amounts) external payable onlyOwner {
        require(amounts.length == _totalRewardTokens, "Wrong amounts");

        uint256 duration = _data.rewardsDuration;
        uint256 periodFinish = _data.periodFinish;

        for (uint256 i = 0; i < _totalRewardTokens;) {
            if (amounts[i] > 0) {
                RewardToken storage rewardToken = _rewardTokens[i + 1];
                uint256 prevBalance = IERC20(rewardToken.token).balanceOf(address(this));
                IERC20(rewardToken.token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    amounts[i]
                );
                uint256 newBalance = IERC20(rewardToken.token).balanceOf(address(this));
                uint256 reward = newBalance - prevBalance;
                if (block.timestamp < periodFinish) {
                    uint256 remaining = periodFinish - block.timestamp;
                    uint256 leftover = remaining * rewardToken.rewardRate;
                    rewardToken.rewardRate = (reward + leftover) / duration;
                } else {
                    rewardToken.rewardRate = reward / duration;
                }  

                require(
                    rewardToken.rewardRate <= newBalance / duration,
                    "Reward too high"
                );

                emit RewardAdded(reward);        
            }

            unchecked {
                ++i;
            }
        }

        _data.lastUpdateTime = uint64(block.timestamp);
        _data.periodFinish = uint64(block.timestamp + duration);
    }

    /**
     * @dev Updates reward amounts for all tokens
     * @param rewards array of reward amounts to update contract with
     */
    function notifyRewardAmount(uint256[] memory rewards) public payable onlyOwner {
        require(rewards.length == _totalRewardTokens, "Wrong reward amounts");

        uint256 periodFinish = _data.periodFinish;
        uint256 duration = _data.rewardsDuration;

        for (uint i = 0; i < _totalRewardTokens;) {
            _updateReward(address(0), i + 1);

            RewardToken storage rewardToken = _rewardTokens[i + 1];

            if (block.timestamp < periodFinish) {
                    uint256 remaining = periodFinish - block.timestamp;
                    uint256 leftover = remaining * rewardToken.rewardRate;
                    rewardToken.rewardRate = (rewards[i] + leftover) / duration;
                } else {
                    rewardToken.rewardRate = rewards[i] / duration;
                }  

            uint256 balance = IERC20(rewardToken.token).balanceOf(address(this));

            require(rewardToken.rewardRate <= balance / duration, "Reward too high");

            emit RewardAdded(rewards[i]);

            unchecked { ++i;}
        }

        _data.lastUpdateTime = uint64(block.timestamp);
        _data.periodFinish = uint64(block.timestamp + duration);
    }

    /**
     * @dev Adds reward token to contract
     * @param token the token to add to contract
     */
    function addRewardToken(address token) external payable onlyOwner {
        require(_totalRewardTokens < 6, "Too many tokens");
        require(IERC20(token).balanceOf(address(this)) > 0, "Must prefund contract");
        require(
            _rewardTokenToIndex[token] == 0,
            "Reward token exists"
        );

        uint256 newTotal = _totalRewardTokens + 1;

        // Increment total reward tokens
        _totalRewardTokens = newTotal;

        // Create new reward token record
        _rewardTokens[newTotal].token = token;

        _rewardTokenToIndex[address(token)] = newTotal;

        uint256[] memory rewardAmounts = new uint256[](newTotal);
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 tokenIndex = newTotal - 1;

        if (IERC20(token) != stakingToken) {
            rewardAmounts[tokenIndex] = balance;
        } else {
            require(
                balance >= rewardAmounts[tokenIndex],
                "Not enough for rewards"
            );
            rewardAmounts[tokenIndex] = balance - _totalSupply;
        }

        notifyRewardAmount(rewardAmounts);
    }

    /**
     * @dev Removes token from rewards
     * @param token the reward token to remove
     * @notice Users will no longer be able to claim rewards
     * for this token. This should be done after period lapses
     * so users can withdraw their expected rewards in time.
     * Use emergencyWithdrawal function to remove tokens
     * prior to calling this function.
     */
    function removeRewardToken(address token) public payable onlyOwner updateReward(address(0)) {
        require(_totalRewardTokens > 1, "Cannot have 0 reward tokens");
        // Get the index of token to remove
        uint indexToDelete = _rewardTokenToIndex[token];

        // Start at index of token to remove. Remove token and move all later indices lower.
        for (uint i = indexToDelete; i <= _totalRewardTokens;) {
            // Get token of one later index
            RewardToken memory rewardToken = _rewardTokens[i + 1];

            // Overwrite existing index with index + 1 record
            _rewardTokens[i] = rewardToken;

            // Delete original
            delete _rewardTokens[i + 1];

            // Set new index
            _rewardTokenToIndex[rewardToken.token] = i;

            unchecked { ++i; }
        }

        _totalRewardTokens -= 1;
    }

    /**
     * @dev Withdraw tokens from contract
     * @param token the token to withdraw
     * @notice The owner cannot withdraw users'
     * staked tokens, only rewards.
     */
    function emergencyWithdrawal(address token) external payable onlyOwner updateReward(address(0)) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Contract holds no tokens");
        IERC20(token).transfer(owner(), balance);
        removeRewardToken(token);
    }

    /**
     * @dev Updates rewards for individual token
     * @param account the user account to update
     * @param tokenIndex the index of the token to update
     */
    function _updateReward(address account, uint256 tokenIndex) private
    {
        RewardToken storage rewardToken = _rewardTokens[tokenIndex];
        uint256 rewardPerTokenStored = _rewardPerTokenStored(tokenIndex);
        rewardToken.rewardPerTokenStored = rewardPerTokenStored;

        if (account != address(0)) {
            address token = rewardToken.token;
            _rewards[account][token] = _earned(account, tokenIndex);
            _userRewardPerTokenPaid[account][token] = rewardPerTokenStored;
        }
    }

    /* === MODIFIERS === */

    /**
     * @dev Updates rewards for all tokens
     * @param account the user account to update
     */
    modifier updateReward(address account) {
        uint256[] memory rewardsPerToken = rewardPerToken();

        for (uint i = 0; i < _totalRewardTokens;) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            uint256 tokenReward = _rewardPerTokenStored(i + 1);
            rewardToken.rewardPerTokenStored = tokenReward;

            if (account != address(0)) {
                uint256 earnings = _earned(account, i + 1);
                _rewards[account][rewardToken.token] = earnings;
                _userRewardPerTokenPaid[account][rewardToken.token] = tokenReward;                
            }

            unchecked { ++i; }
        }

        _data.lastUpdateTime = uint64(lastTimeRewardApplicable());
        _;
    }

    /* === EVENTS === */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}