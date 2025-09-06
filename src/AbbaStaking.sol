// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// Import OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Define the AbbaStaking contract
contract AbbaStaking is ReentrancyGuard, Ownable, Pausable {

// Use SafeERC20 for safe token operations
    using SafeERC20 for IERC20;
    IERC20 public stakingToken;
    IERC20 public rewardToken;

// Staking data structures
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

// Reward parameters
    uint256 public rewardRate = 500; // Reward rate per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public minLockPeriod = 1 days; // Minimum lock period
    uint256 public maxLockPeriod = 90 days; // Maximum lock period

// Staking balances
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

// Lock and fee parameters
    mapping(address => uint256) public userLockPeriod;
    mapping(address => uint256) public lastStakedTime;
    uint256 public earlyUnstakeFee = 50; // 5% fee for early unstaking
    address public feeRecipient;

    constructor(address _stakingToken, address _rewardToken, address _feeRecipient) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);

        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        lastUpdateTime = block.timestamp;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
// Pausable functions
    function pause() external onlyOwner {
        _pause();
    }
// Unpausable functions
    function unpause() external onlyOwner {
        _unpause();
    }
// Total supply and balance functions
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
// Balance of a specific account
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
// Reward calculation functions
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((block.timestamp - lastUpdateTime) * rewardRate * 1e18) /
            _totalSupply;
    }
// Earned rewards for a specific account
    function earned(address account) public view returns (uint256) {
        return
            (_balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }
// Stake function with lock period
    function stake(uint256 amount, uint256 lockPeriod)
        external
        nonReentrant whenNotPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        require(lockPeriod >= minLockPeriod && lockPeriod <= maxLockPeriod, "Invalid lock period");

        _totalSupply += amount;
        _balances[msg.sender] += amount;

        userLockPeriod[msg.sender] = lockPeriod;
        lastStakedTime[msg.sender] = block.timestamp;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }
// Withdraw function with early unstake fee
    function withdraw(uint256 amount)
        public
        nonReentrant whenNotPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        uint256 fee = 0;

        if (block.timestamp < lastStakedTime[msg.sender] + userLockPeriod[msg.sender]) {
            fee = (amount * earlyUnstakeFee) / 1000;
            stakingToken.safeTransfer(feeRecipient, fee);
            emit EarlyUnstakeFeePaid(msg.sender, fee);
        }
        stakingToken.safeTransfer(msg.sender, amount - fee);
        emit Withdrawn(msg.sender, amount);
    }
// Get reward function
    function getReward() public nonReentrant updateReward(msg.sender) whenNotPaused {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            uint256 available = rewardToken.balanceOf(address(this));
            require(available >= reward, "Insufficient reward balance");
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }
// Exit function to withdraw stake and claim rewards
    function exit() external whenNotPaused {
        withdraw(_balances[msg.sender]);
        getReward();
    }
// Administrative functions to set parameters
    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) whenNotPaused {
        uint old = rewardRate;
         require(_rewardRate <= 10000, "Reward rate too high"); // Max 100%
        rewardRate = _rewardRate;
        emit RewardRateUpdated(old, _rewardRate);
    }
// Administrative functions to set lock periods
    function setLockPeriod(uint256 _min, uint256 _max) external onlyOwner whenNotPaused {
        require(_min >= 1 days && _max <= 90 days, "Lock period must be between 1 and 90 days");
        require(_min < _max, "Min lock period must be less than max");
        minLockPeriod = _min;
        maxLockPeriod = _max;
        emit LockPeriodUpdated(_min, _max);
    }
// Adminstrative function to Set early unstake fee
    function setEarlyUnstakeFee(uint256 _earlyUnstakeFee) external onlyOwner whenNotPaused {
        require(_earlyUnstakeFee <= 100, "Fee too high"); // Max 10%
        earlyUnstakeFee = _earlyUnstakeFee;
        emit EarlyUnstakeFeeUpdated(_earlyUnstakeFee);
    }
// Administrative function to set fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner whenNotPaused {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
// Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event EarlyUnstakeFeePaid(address indexed user, uint256 fee);
    event RewardRateUpdated(uint256 oldRewardRate, uint256 newRewardRate);
    event LockPeriodUpdated(uint256 newMinLockPeriod, uint256 newMaxLockPeriod);
    event EarlyUnstakeFeeUpdated(uint256 newEarlyUnstakeFee);
    event FeeRecipientUpdated(address newFeeRecipient);

}


   