//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./helpers/ReentrancyGuard.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

//solhint-disable not-rely-on-time
contract MultiRewardsStake is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    uint256 public periodFinish;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    address public rewardsDistributor;
    
    mapping(address => mapping (address => uint256)) private _userRewardPerTokenPaid;
    mapping(address => mapping (address => uint256)) private _rewards;

    uint256 private _totalRewardTokens;
    mapping (uint => RewardToken) private _rewardTokens;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    struct RewardToken {
        address token;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }

    constructor(
        address rewardsDistributor_,
        address[] memory rewardTokens_,
        address stakingToken_
    ) {
        rewardsDistributor = rewardsDistributor_;
        stakingToken = IERC20(stakingToken_);
        _totalRewardTokens = rewardTokens_.length;

        for (uint i; i < rewardTokens_.length; i++) {
            _rewardTokens[i + 1] = RewardToken({
                token: rewardTokens_[i],
                rewardRate: 0,
                rewardPerTokenStored: 0
            });
        }

        rewardsDuration = 7 days;
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

    function rewardPerToken() public view returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](_totalRewardTokens);
        if (_totalSupply == 0) {
            for (uint i = 0; i < _totalRewardTokens; i++) {
                tokens[i] = _rewardTokens[i + 1].rewardPerTokenStored;
            }
        } else {
            for (uint i = 0; i < _totalRewardTokens; i++) {
                RewardToken storage rewardToken = _rewardTokens[i + 1];
                tokens[i] = rewardToken.rewardPerTokenStored.add(
                    lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardToken.rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
                );
            }
        }

        return tokens;
    }

    function getRewardTokens() public view returns (RewardToken[] memory) {
        RewardToken[] memory tokens = new RewardToken[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens; i++) {
            tokens[i] = _rewardTokens[i + 1];
        }

        return tokens;
    }

    function earned(address account) public view returns (uint256[] memory) {
        uint256[] memory earnings = new uint256[](_totalRewardTokens);
        uint256[] memory tokenRewards = rewardPerToken();
        for (uint i = 0; i < _totalRewardTokens; i++) {
            address token = _rewardTokens[i + 1].token;
            earnings[i] = _balances[account]
                .mul(tokenRewards[i]
                    .sub(_userRewardPerTokenPaid[account][token])
                )
                .div(1e18)
                .add(_rewards[account][token]);
        }

        return earnings;
    }

    function getRewardForDuration() external view returns (uint256[] memory) {
        uint256[] memory currentRewards = new uint256[](_totalRewardTokens);
        for (uint i = 0; i < _totalRewardTokens; i++) {
            currentRewards[i] = _rewardTokens[i + 1].rewardRate.mul(rewardsDuration);
        }

        return currentRewards;
    }

    /* MUTATIONS */

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        // event
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        // event
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        for (uint i = 0; i < _totalRewardTokens; i++) {
            uint256 currentReward = _rewards[msg.sender][_rewardTokens[i + 1].token];
            if (currentReward > 0) {
                _rewards[msg.sender][_rewardTokens[i + 1].token] = 0;
                IERC20(_rewardTokens[i + 1].token).safeTransfer(msg.sender, currentReward);
                // event
            }
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* RESTRICTED FUNCTIONS */

    function notifyRewardAmount(uint256[] memory reward) external onlyDistributor updateReward(address(0)) {
        require(reward.length == _totalRewardTokens, "Wrong reward amounts");
        for (uint i = 0; i < _totalRewardTokens; i++) {
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
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);

        // event
    }

    function addRewardToken(address token) external onlyDistributor updateReward(address(0)) {
        require(IERC20(token).balanceOf(address(this)) > 0, "Must prefund contract");
        _totalRewardTokens += 1;
        _rewardTokens[_totalRewardTokens] = RewardToken({
            token: token,
            rewardRate: IERC20(token).balanceOf(address(this)).div(rewardsDuration),
            rewardPerTokenStored: 0
        });

    }

    /* MODIFIERS */

    modifier updateReward(address account) {
        uint256[] memory currentRewardPerToken = rewardPerToken();
        uint256[] memory currentEarnings = earned(account);
        lastUpdateTime = lastTimeRewardApplicable();
        for (uint i = 0; i < _totalRewardTokens; i++) {
            RewardToken storage rewardToken = _rewardTokens[i + 1];
            rewardToken.rewardPerTokenStored = currentRewardPerToken[i];
            if (account != address(0)) {
                _rewards[account][rewardToken.token] = currentEarnings[i];
                _userRewardPerTokenPaid[account][rewardToken.token] = currentRewardPerToken[i];                
            }
        }
        _;
    }

    modifier onlyDistributor() {
        require(msg.sender == rewardsDistributor, "Call not distributor");
        _;
    }
}