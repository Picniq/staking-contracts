// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";
import "./libraries/SafeERC20.sol";

// solhint-disable not-rely-on-time
contract SingleAssetStake {
    using SafeERC20 for IERC20;

    RewardState private _state;

    IERC20 public rewardToken;
    IERC20 public stakingToken;

    uint256 private _totalSupply;
    mapping (address => uint256) private _userRewardPerTokenPaid;
    mapping (address => uint256) private _rewards;
    mapping (address => uint256) private _balances;

    struct RewardState {
        uint64 periodFinish;
        uint64 rewardsDuration;
        uint64 lastUpdateTime;
        uint160 distributor;
        uint160 factory;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }

    constructor(address distributor, address stakingToken_, address rewardToken_, uint64 duration) {
        _state.distributor = uint160(distributor);
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        _state.rewardsDuration = duration;
    }

    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256)
    {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256)
    {
        return Math.min(block.timestamp, _state.periodFinish);
    }

    function rewardPerToken() public view returns (uint256)
    {
        uint256 supply = _totalSupply;

        if (supply == 0) {
            return _state.rewardPerTokenStored;
        }

        return _state.rewardPerTokenStored + (
            (lastTimeRewardApplicable() - _state.lastUpdateTime) * _state.rewardRate * 1e18 / supply
        );
    }

    function earned(address account) public view returns (uint256)
    {
        return _balances[account] * (
            rewardPerToken() - _userRewardPerTokenPaid[account]
        ) / 1e18 + _rewards[account];
    }

    function getRewardForDuration() external view returns (uint256)
    {
        return _state.rewardRate * _state.rewardsDuration;
    }

    function stake(uint256 amount) external payable updateReward(msg.sender)
    {
        require(amount > 0, "Must be greater than zero");
        _totalSupply += amount;
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public payable updateReward(msg.sender)
    {
        require(amount > 0, "Must be greater than zero");

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public updateReward(msg.sender)
    {
        uint256 reward = _rewards[msg.sender];

        if (reward > 0) {
            _rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);

            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external payable
    {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 reward) external payable updateReward(address(0))
    {
        require(msg.sender == address(_state.distributor), "Not distributor");

        uint256 duration = _state.rewardsDuration;
        uint256 rewardRate = _state.rewardRate;
        uint256 timestamp = block.timestamp;
        uint256 periodFinish = _state.periodFinish;

        if (timestamp >= periodFinish) {
            _state.rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - timestamp;
            uint256 leftover = remaining * rewardRate;
            _state.rewardRate = (rewardRate + leftover) / duration;
        }

        uint256 balance = rewardToken.balanceOf(address(this));

        if (rewardToken == stakingToken) {
            balance -= _totalSupply;
        }

        require(_state.rewardRate <= balance / duration, "Reward too high");

        _state.lastUpdateTime = uint64(timestamp);
        _state.periodFinish = uint64(timestamp + duration);

        emit RewardAdded(reward);
    }

    modifier updateReward(address account) {
        _state.rewardPerTokenStored = rewardPerToken();
        _state.lastUpdateTime = uint64(lastTimeRewardApplicable());

        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = _state.rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}