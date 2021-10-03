// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Token.sol";

// MasterChef is the master of Token. He can make Token and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Token is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Tokens to distribute per second.
        uint256 lastRewardTime;  // Last timestamp that Tokens distribution occurs.
        uint256 accTokenPerShare;   // Accumulated Tokens per share, times 1e12. See below.
        uint16 withdrawFeeBP;      // Deposit fee in basis points
    }

    // The TOKEN!
    Token public token;
    // Maximum emission rate
    uint256 public maxEmissionRate = 1 ether;
    // Dev address.
    address public devaddr;
    // Token tokens created per second.
    uint256 public tokenPerSecond;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The timestamp when Token mining starts.
    uint256 public startTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 tokenPerSecond);
    event AddPool(uint256 pid, address lp, uint256 allocPoint, uint256 fee);
    event SetPool(uint256 pid, uint256 allocPoint, uint256 fee);
    event SetStartTime(uint256 startTime);

    constructor(
        Token _token,
        address _devaddr,
        address _feeAddress,
        uint256 _tokenPerSecond,
        uint256 _startTimestamp
    ) {
        require(_feeAddress != address(0), "no zero address");
        require(_devaddr != address(0), "no zero address");
        token = _token;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        tokenPerSecond = _tokenPerSecond;
        startTimestamp = _startTimestamp;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _withdrawFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_withdrawFeeBP <= 400, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        // balanceOf check
        // this should be works fine if address is a token
        uint256 balance = _lpToken.balanceOf(address(this));

        uint256 lastRewardTime = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardTime : lastRewardTime,
        accTokenPerShare : 0,
        withdrawFeeBP : _withdrawFeeBP
        }));

        emit AddPool(poolInfo.length.sub(1), address(_lpToken), _allocPoint, _withdrawFeeBP);
    }

    // Update the given pool's Token allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _withdrawFeeBP, bool _withUpdate) public onlyOwner {
        require(_withdrawFeeBP <= 400, "add: invalid withdrawal fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        emit SetPool(_pid, _allocPoint, _withdrawFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending Tokens on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // CHANGED
        if (lpSupply == 0 || totalAllocPoint == 0) return 0;

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        token.mint(devaddr, tokenReward.div(10));
        token.mint(address(this), tokenReward);
        uint256 burnAmount = tokenReward.mul(2).div(100);

        safeTokenTransfer(0x000000000000000000000000000000000000dEaD, burnAmount);

        tokenReward = tokenReward.sub(burnAmount);

        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for Token allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 finalAmount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            user.amount = user.amount.add(finalAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 fee = 0;
            if (pool.withdrawFeeBP > 0) {
                // Changed
                fee = _amount.mul(pool.withdrawFeeBP).div(100);
                pool.lpToken.safeTransfer(feeAddress, fee);
            }
            pool.lpToken.safeTransfer(address(msg.sender), _amount.sub(fee));
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 fee = 0;
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        if (pool.withdrawFeeBP > 0) {
            // changed
            fee = user.amount.mul(pool.withdrawFeeBP).div(10000);
            amount = amount.sub(fee);
            pool.lpToken.safeTransfer(feeAddress, fee);
        }
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough Tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = token.transfer(_to, tokenBal);
        } else {
            transferSuccess = token.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "no zero address");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "no zero address");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _tokenPerSecond) external onlyOwner {
        require(_tokenPerSecond <= 1 ether, "Maximum exceeded");
        massUpdatePools();
        tokenPerSecond = _tokenPerSecond;
        emit UpdateEmissionRate(msg.sender, _tokenPerSecond);
    }

    function setStartTime(uint256 _startTimestamp) external onlyOwner {
        require(block.timestamp < startTimestamp, "It's too late to postpone mining. It has already started");
        require(_startTimestamp > startTimestamp, "Cannot set to past timestamp");
        startTimestamp = _startTimestamp;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardTime = _startTimestamp;
        }

        emit SetStartTime(_startTimestamp);
    }
}
