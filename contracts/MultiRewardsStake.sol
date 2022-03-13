//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ReentrancyGuard.sol";
import "./helpers/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

//solhint-disable not-rely-on-time
contract MultiRewardsStake is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Base staking info
    IERC20 public stakingToken;
    uint256 public periodFinish;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    
    // User reward info
    mapping(address => mapping (address => uint256)) private _userRewardPerTokenPaid;
    mapping(address => mapping (address => uint256)) private _rewards;

    // Reward token data
    uint256 private _totalRewardTokens;
    mapping (uint => RewardToken) private _rewardTokens;
    mapping (address => uint) private _rewardTokenToIndex;

    // User deposit data
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // Store reward token data
    struct RewardToken {
        address token;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }

    constructor(
        address[] memory rewardTokens_,
        address stakingToken_
    ) {
        stakingToken = IERC20(stakingToken_);
        _totalRewardTokens = rewardTokens_.length;

        for (uint i; i < _totalRewardTokens;) {
            _rewardTokens[i + 1] = RewardToken({
                token: rewardTokens_[i],
                rewardRate: 0,
                rewardPerTokenStored: 0
            });
            _rewardTokenToIndex[rewardTokens_[i]] = i + 1;

            unchecked { ++i; }
        }

        rewardsDuration = 14 days;
    }

    /* VIEWS */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function totalRewardTokens() external view returns (uint256) {
        return _totalRewardTokens;
    }

    // Get reward rate for all tokens
    function rewardPerToken() external view returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens;) {
            tokens[i] = _rewardPerTokenStored(i + 1);
            unchecked { ++i; }
        }

        return tokens;
    }

    // Get reward rate for individual token
    function rewardForToken(address token) external view returns (uint256) {
        uint256 index = _rewardTokenToIndex[token];
        return _rewardPerTokenStored(index);
    }

    // Internal function to calculate rewardPerTokenStored
    function _rewardPerTokenStored(uint tokenIndex) private view returns (uint256) {
        if (_totalSupply == 0) {
            return _rewardTokens[tokenIndex].rewardPerTokenStored;
        }
        return _rewardTokens[tokenIndex].rewardPerTokenStored.add(
            lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(_rewardTokens[tokenIndex].rewardRate)
            .mul(1e18)
            .div(_totalSupply)
        );
    }

    function getRewardTokens() external view returns (RewardToken[] memory) {
        RewardToken[] memory tokens = new RewardToken[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens; i++) {
            tokens[i] = _rewardTokens[i + 1];
        }

        return tokens;
    }

    function earned(address account) external view returns (uint256[] memory) {
        uint256[] memory earnings = new uint256[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens;) {
            earnings[i] = _earned(account, i + 1);

            unchecked { ++i; }
        }

        return earnings;
    }

    function _earned(address account, uint256 tokenIndex) private view returns (uint256) {
        address token = _rewardTokens[tokenIndex].token;
        uint256 tokenReward = _rewardPerTokenStored(tokenIndex);
        return _balances[account].mul(tokenReward
            .sub(
                _userRewardPerTokenPaid[account][token])
            )
            .div(1e18)
            .add(_rewards[account][token]
        );
    }

    function getRewardForDuration() external view returns (uint256[] memory) {
        uint256[] memory currentRewards = new uint256[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens;) {
            currentRewards[i] = _rewardTokens[i + 1].rewardRate.mul(rewardsDuration);
            unchecked { ++i; }
        }

        return currentRewards;
    }

    /* === MUTATIONS === */

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        uint256 currentBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBalance = stakingToken.balanceOf(address(this));
        uint256 supplyDiff = newBalance.sub(currentBalance);
        _totalSupply = _totalSupply.add(supplyDiff);
        _balances[msg.sender] = _balances[msg.sender].add(supplyDiff);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        for (uint i = 0; i < _totalRewardTokens;) {
            uint256 currentReward = _rewards[msg.sender][_rewardTokens[i + 1].token];
            if (currentReward > 0) {
                _rewards[msg.sender][_rewardTokens[i + 1].token] = 0;
                IERC20(_rewardTokens[i + 1].token).safeTransfer(msg.sender, currentReward);
                emit RewardPaid(msg.sender, currentReward);
            }

            unchecked { ++i; }
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* === RESTRICTED FUNCTIONS === */

    function depositRewardTokens(uint256[] memory amount) external onlyOwner {
        require(amount.length == _totalRewardTokens, "Wrong amounts");

        for (uint i = 0; i < _totalRewardTokens;) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            uint256 prevBalance = IERC20(rewardToken.token).balanceOf(address(this));
            IERC20(rewardToken.token).safeTransferFrom(msg.sender, address(this), amount[i]);
            uint reward = IERC20(rewardToken.token).balanceOf(address(this)).sub(prevBalance);
            if (block.timestamp >= periodFinish) {
                rewardToken.rewardRate = reward.div(rewardsDuration);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardToken.rewardRate);
                rewardToken.rewardRate = reward.add(leftover).div(rewardsDuration);
            }

            uint256 balance = IERC20(rewardToken.token).balanceOf(address(this));
            require(rewardToken.rewardRate <= balance.div(rewardsDuration), "Reward too high");
            emit RewardAdded(reward);

            unchecked { ++i; }
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);

        // notifyRewardAmount(newRewards);
    }

    function notifyRewardAmount(uint256[] memory reward) public onlyOwner updateReward(address(0)) {
        require(reward.length == _totalRewardTokens, "Wrong reward amounts");
        for (uint i = 0; i < _totalRewardTokens;) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            if (block.timestamp >= periodFinish) {
                rewardToken.rewardRate = reward[i].div(rewardsDuration);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardToken.rewardRate);
                rewardToken.rewardRate = reward[i].add(leftover).div(rewardsDuration);
            }

            uint256 balance = IERC20(rewardToken.token).balanceOf(address(this));
            require(rewardToken.rewardRate <= balance.div(rewardsDuration), "Reward too high");
            emit RewardAdded(reward[i]);

            unchecked { ++i; }
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
    }

    function addRewardToken(address token) external onlyOwner {
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
        if (token != address(stakingToken)) {
            rewardAmounts[tokenIndex] = balance;
        } else {
            require(balance >= rewardAmounts[tokenIndex], "Not enough for rewards");
            rewardAmounts[tokenIndex] = balance.sub(_totalSupply);
        }

        notifyRewardAmount(rewardAmounts);
    }

    function removeRewardToken(address token) public onlyOwner updateReward(address(0)) {
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

    function emergencyWithdrawal(address token) external onlyOwner updateReward(address(0)) {
        require(_rewardTokenToIndex[token] != 0, "Not a reward token");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Contract holds no tokens");
        if (address(stakingToken) == token) {
            uint256 amountToWithdraw = balance.sub(_totalSupply);
            IERC20(token).safeTransfer(owner(), amountToWithdraw);
        } else {
            IERC20(token).safeTransfer(owner(), balance);
        }
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