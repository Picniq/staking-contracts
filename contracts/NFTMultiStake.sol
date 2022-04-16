// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./helpers/ReentrancyGuard.sol";
import "./helpers/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./libraries/Math.sol";
import "./libraries/SafeERC20.sol";

// solhint-disable not-rely-on-time
contract NFTMultiStake is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Base staking info
    IERC721 public stakingNFT;
    uint256 public periodFinish;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;

    // User deposit data
    uint256 private _totalSupply;
    mapping (address => uint256[]) private _balances;

    // User reward info
    mapping (address => mapping (address => uint256)) private _userRewardPerTokenPaid;
    mapping (address => mapping (address => uint256)) private _rewards;

    // Reward token data
    uint256 private _totalRewardTokens;
    mapping (uint256 => RewardToken) private _rewardTokens;
    mapping (address => uint256) private _rewardTokenToIndex;

    // Store reward token data
    struct RewardToken {
        address token;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }

    constructor(
        address[] memory rewardTokens_,
        address stakingNFT_
    ) {
        stakingNFT = IERC721(stakingNFT_);
        _totalRewardTokens = rewardTokens_.length;

        for (uint256 i; i < _totalRewardTokens;) {
            _rewardTokens[i + 1] = RewardToken({
                token: rewardTokens_[i],
                rewardRate: 0,
                rewardPerTokenStored: 0
            });
            _rewardTokenToIndex[rewardTokens_[i]] = i + 1;

            unchecked { ++ i; }
        }

        rewardsDuration = 365 days;

    }

    /* VIEWS */

    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256)
    {
        return _balances[account].length;
    }

    function stakedNFTs(address account) external view returns (uint256[] memory)
    {
        return _balances[account];
    }

    function indexOfStaked(address account, uint256 id) external view returns (uint256)
    {
        uint256[] memory ids = _balances[account];
        for (uint i = 0; i < ids.length;) {
            if (ids[i] == id) {
                return i;
            }

            unchecked { ++i; }
        }

        // This should only get here if id is not found
        return type(uint256).max;
    }

    function lastTimeRewardApplicable() public view returns (uint256)
    {
        return Math.min(block.timestamp, periodFinish);
    }

    function totalRewardTokens() external view returns (uint256)
    {
        return _totalRewardTokens;
    }

    function rewardPerToken() external view returns (uint256[] memory)
    {
        uint256[] memory tokens;

        for (uint256 i = 0; i < _totalRewardTokens;) {
            tokens[i] = _rewardPerTokenStored(i + 1);
            unchecked { ++i; }
        }

        return tokens;
    }

    function rewardForToken(address token) external view returns (uint256)
    {
        uint256 index = _rewardTokenToIndex[token];
        return _rewardPerTokenStored(index);
    }

    function _rewardPerTokenStored(uint256 tokenIndex) private view returns (uint256)
    {
        RewardToken memory rewardToken = _rewardTokens[tokenIndex];

        if (_totalSupply == 0) {
            return rewardToken.rewardPerTokenStored;
        }

        return rewardToken.rewardPerTokenStored + (
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardToken.rewardRate * 1e18 / _totalSupply
        );
    }

    function getRewardTokens() external view returns (RewardToken[] memory)
    {
        RewardToken[] memory tokens = new RewardToken[](_totalRewardTokens);

        for (uint i = 0; i < _totalRewardTokens;) {
            tokens[i] = _rewardTokens[i + 1];
            unchecked { ++i; }
        }

        return tokens;
    }

    function earned(address account) external view returns (uint256[] memory)
    {
        uint256[] memory earnings = new uint256[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens;) {
            earnings[i] = _earned(account, i + 1);

            unchecked { ++i; }
        }

        return earnings;
    }

    function _earned(address account, uint256 tokenIndex) private view returns (uint256)
    {
        address token = _rewardTokens[tokenIndex].token;
        uint256 tokenReward = _rewardPerTokenStored(tokenIndex);
        return _balances[account].length * (tokenReward - _userRewardPerTokenPaid[account][token]) / 1e18 + _rewards[account][token];
    }

    function getRewardForDuration() external view returns (uint256[] memory)
    {
        uint256[] memory currentRewards = new uint256[](_totalRewardTokens);

        for (uint i = 0; i < _totalRewardTokens;) {
            currentRewards[i] = _rewardTokens[i + 1].rewardRate * rewardsDuration;
            unchecked { ++i; }
        }

        return currentRewards;
    }

    /* MUTATIONS */

    function stake(uint256 tokenId) external payable nonReentrant updateReward(msg.sender)
    {
        stakingNFT.safeTransferFrom(msg.sender, address(this), tokenId);
        _totalSupply += 1;
        uint256[] memory ids = _balances[msg.sender];
        ids[ids.length] = tokenId;
        _balances[msg.sender] = ids;
    }

    function withdraw(uint256 index) public payable nonReentrant updateReward(msg.sender)
    {
        require(_balances[msg.sender].length > 0, "No NFTs staked");
        _totalSupply -= 1;
        uint256[] memory staked = _balances[msg.sender];
        uint256 id = staked[index];
        stakingNFT.safeTransferFrom(address(this), msg.sender, id);
        delete _balances[msg.sender][index];
    }

    function depositRewardTokens(uint256[] memory amount) external payable onlyOwner
    {
        require(amount.length == _totalRewardTokens, "Wrong amounts");

        for (uint i = 0; i < _totalRewardTokens;) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            uint256 prevBalance = IERC20(rewardToken.token).balanceOf(address(this));
            IERC20(rewardToken.token).safeTransferFrom(msg.sender, address(this), amount[i]);
            uint reward = IERC20(rewardToken.token).balanceOf(address(this)) - prevBalance;
            if (block.timestamp >= periodFinish) {
                rewardToken.rewardRate = reward / rewardsDuration;
            } else {
                uint256 remaining = periodFinish - block.timestamp;
                uint256 leftover = remaining * rewardToken.rewardRate;
                rewardToken.rewardRate = (reward + leftover) / rewardsDuration;
            }

            uint256 balance = IERC20(rewardToken.token).balanceOf(address(this));
            require(rewardToken.rewardRate <= balance / rewardsDuration, "Reward too high");
            emit RewardAdded(reward);

            unchecked { ++i; }
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        // notifyRewardAmount(newRewards);
    }

    function notifyRewardAmount(uint256[] memory reward) public payable onlyOwner updateReward(address(0))
    {
        require(reward.length == _totalRewardTokens, "Wrong reward amounts");
        for (uint i = 0; i < _totalRewardTokens;) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            if (block.timestamp >= periodFinish) {
                rewardToken.rewardRate = reward[i] / rewardsDuration;
            } else {
                uint256 remaining = periodFinish - block.timestamp;
                uint256 leftover = remaining * rewardToken.rewardRate;
                rewardToken.rewardRate = (reward[i] + leftover) / rewardsDuration;
            }

            uint256 balance = IERC20(rewardToken.token).balanceOf(address(this));
            require(rewardToken.rewardRate <= balance / rewardsDuration, "Reward too high");
            emit RewardAdded(reward[i]);

            unchecked { ++i; }
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
    }

    function addRewardToken(address token) external payable onlyOwner {
        require(_totalRewardTokens < 6, "Too many tokens");
        require(IERC20(token).balanceOf(address(this)) > 0, "Must prefund contract");
        require(_rewardTokenToIndex[token] == 0, "Reward token exists");

        // Increment total reward tokens
        _totalRewardTokens += 1;

        // Create new reward token record
        _rewardTokens[_totalRewardTokens] = RewardToken({
            token: token,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });

        _rewardTokenToIndex[token] = _totalRewardTokens;

        uint256[] memory rewardAmounts = new uint256[](_totalRewardTokens);

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 tokenIndex = _totalRewardTokens - 1;
        
        require(balance >= rewardAmounts[tokenIndex], "Not enough for rewards");
        rewardAmounts[tokenIndex] = balance - _totalSupply;

        notifyRewardAmount(rewardAmounts);
    }

    function removeRewardToken(address token) public payable onlyOwner updateReward(address(0)) {
        require(_totalRewardTokens > 1, "Cannot have 0 reward tokens");
        // Get the index of token to remove
        uint indexToDelete = _rewardTokenToIndex[token];

        // Start at index of token to remove. Remove token and move all later indices lower.
        for (uint i = indexToDelete; i <= _totalRewardTokens;) {
            // Get token of one later index
            RewardToken storage rewardToken = _rewardTokens[i + 1];

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

    function emergencyWithdrawal(address token) external payable onlyOwner updateReward(address(0)) {
        require(_rewardTokenToIndex[token] != 0, "Not a reward token");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Contract holds no tokens");
        IERC20(token).safeTransfer(owner(), balance);
        removeRewardToken(token);
    }

    /* === MODIFIERS === */

    modifier updateReward(address account) {
        lastUpdateTime = lastTimeRewardApplicable();
        for (uint i = 0; i < _totalRewardTokens;) {
            uint256 index = i + 1;
            uint256 rewardPerTokenStored = _rewardPerTokenStored(index);
            RewardToken storage rewardToken = _rewardTokens[index];
            rewardToken.rewardPerTokenStored = rewardPerTokenStored;
            if (account != address(0)) {
                _rewards[account][rewardToken.token] = _earned(account, index);
                _userRewardPerTokenPaid[account][rewardToken.token] = rewardPerTokenStored;                
            }

            unchecked { ++i; }
        }
        _;
    }

    /* === EVENTS === */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}