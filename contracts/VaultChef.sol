// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "./interfaces/ITreasury.sol";
import "./interfaces/IStrategy.sol";

contract VaultChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 shares;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 want;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardsPerShare;
        address strat;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;

    IERC20 public usdc;
    ITreasury public treasury;

    uint256 public emissionRate;
    uint256 public rateMultiplierBP = 10000;
    uint256 public lastEmissionUpdateBlock;
    address public schedulerAddress = address(0xa6A5dd2ca182464B90A0D53DdeB16183f49668D3);

    address constant public busdAddress = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositBUSD(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateVaultEmission(address indexed user, uint256 emissionRate);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event SetSchedulerAddress(address indexed user, address newAddr);
    event SetRateMultiplier(address indexed user, uint256 rate);
    event Earn(address indexed user, uint256 indexed pid, address wantAddress, uint256 amountGained, uint256 valueGained);

    constructor(
        address _treasury,
        address _usdc
    ) public {
        treasury = ITreasury(_treasury);
        usdc = IERC20(_usdc);
    }

    modifier onlyAdmins(){
        require(msg.sender == owner() || msg.sender == schedulerAddress, "onlyAdmins: FORBIDDEN");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _allocPoint, IERC20 _want, bool _withUpdate, address _strat) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        want : _want,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accRewardsPerShare : 0,
        strat : _strat
        }));
    }

    // Update the given pool's AUTO allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256){
        return _to.sub(_from);
    }

    function pendingRewards(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 rewards = multiplier.mul(emissionRate).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(rewards.mul(1e12).div(sharesTotal));
        }
        return user.shares.mul(accRewardsPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function massUpdatePoolsFromTo(uint256 from, uint256 to) public {
        for (uint256 pid = from; pid <= to; ++pid) {
            updatePool(pid);
        }
    }

    function updateVaultEmission(bool withUpdate) public onlyAdmins {
        if (withUpdate) {
            massUpdatePools();
        }
        uint256 _emissionRate = treasury.updateEmissionRate();
        emissionRate = _emissionRate.mul(rateMultiplierBP).div(10000);
        lastEmissionUpdateBlock = block.number;
        emit UpdateVaultEmission(msg.sender, emissionRate);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }
        uint256 rewards = multiplier.mul(emissionRate).mul(pool.allocPoint).div(totalAllocPoint);
        rewards = treasury.mintGooseDollar(rewards);

        pool.accRewardsPerShare = pool.accRewardsPerShare.add(rewards.mul(1e12).div(sharesTotal));
        pool.lastRewardBlock = block.number;
    }

    // Want tokens moved from user -> chef -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 pending = user.shares.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }
        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(address(msg.sender), address(this), _wantAmt);
            pool.want.safeIncreaseAllowance(pool.strat, _wantAmt);
            uint256 sharesAdded = IStrategy(pool.strat).deposit(msg.sender, _wantAmt);
            require(sharesAdded > 0, "DEPOSIT FAILED");
            user.shares = user.shares.add(sharesAdded);
        }
        user.rewardDebt = user.shares.mul(pool.accRewardsPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    function depositBUSD(uint256 _pid, uint256 _busdAmount) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 pending = user.shares.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }
        if (_busdAmount > 0) {
            IERC20(busdAddress).safeTransferFrom(address(msg.sender), address(this), _busdAmount);
            IERC20(busdAddress).safeIncreaseAllowance(pool.strat, _busdAmount);
            uint256 sharesAdded = IStrategy(pool.strat).depositBUSD(msg.sender, _busdAmount);
            require(sharesAdded > 0, "DEPOSIT FAILED");
            user.shares = user.shares.add(sharesAdded);
        }
        user.rewardDebt = user.shares.mul(pool.accRewardsPerShare).div(1e12);
        emit DepositBUSD(msg.sender, _pid, _busdAmount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(pool.strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        uint256 pending = user.shares.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
        }

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = IStrategy(pool.strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = pool.want.balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(msg.sender), _wantAmt);
        }
        user.rewardDebt = user.shares.mul(pool.accRewardsPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, type(uint128).max);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(pool.strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        IStrategy(pool.strat).withdraw(msg.sender, amount);

        pool.want.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    // Safe transfer function, just in case if rounding error causes pool to not have enough
    function safeRewardTransfer(address to, uint256 amount) internal {
        uint256 balance = usdc.balanceOf(address(this));
        if (amount > balance) {
            usdc.safeTransfer(to, balance);
        } else {
            usdc.safeTransfer(to, amount);
        }
    }

    function harvestFor(uint256 _pid, address _user) public nonReentrant {
        //Limit to self or delegated harvest to avoid unnecessary confusion
        require(msg.sender == _user || tx.origin == _user, "harvestFor: FORBIDDEN");
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (user.shares > 0) {
            uint256 pending = user.shares.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeRewardTransfer(_user, pending);
                user.rewardDebt = user.shares.mul(pool.accRewardsPerShare).div(1e12);
                emit Harvest(_user, _pid, pending);
            }
        }
    }

    function bulkHarvestFor(uint256[] calldata pidArray, address _user) external {
        uint256 length = pidArray.length;
        for (uint256 index = 0; index < length; ++index) {
            uint256 _pid = pidArray[index];
            harvestFor(_pid, _user);
        }
    }

    function earn(uint256 _pid) external onlyAdmins {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 wantLockedBefore = IStrategy(pool.strat).wantLockedTotal();
        IStrategy(pool.strat).earn();
        uint256 wantLockedAfter = IStrategy(pool.strat).wantLockedTotal();
        if(wantLockedAfter > wantLockedBefore){
            uint256 wantGained = wantLockedAfter.sub(wantLockedBefore);
            uint256 valueGained = IStrategy(pool.strat).wantTokenValue(wantGained);
            emit Earn(msg.sender, _pid, address(pool.want), wantGained, valueGained);
        }
    }




    //Misc Settings
    function setSchedulerAddr(address newAddr) external onlyAdmins {
        schedulerAddress = newAddr;
        emit SetSchedulerAddress(msg.sender, newAddr);
    }

    function setRateMultiplier(uint256 rate) external onlyOwner {
        rateMultiplierBP = rate;
        emit SetRateMultiplier(msg.sender, rate);
    }



    //View Functions For Clients
    function tvl(uint256 _pid) public view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).tvl();
    }

    function sharesTotal(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).sharesTotal();
    }

    function wantLockedTotal(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).wantLockedTotal();
    }

    function lastEarnBlock(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).lastEarnBlock();
    }

    function lastEarnTimestamp(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).lastEarnTimestamp();
    }

    function wantTokenValue(uint256 _pid, uint256 wantAmount) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).wantTokenValue(wantAmount);
    }

    function originTVL(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).originTVL();
    }

    function rewardTokenValue(uint256 _pid, uint256 rewardAmount) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).rewardTokenValue(rewardAmount);
    }

    function originRewardsPerBlock(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).originRewardsPerBlock();
    }

    function originAPR(uint256 _pid, uint256 blocks) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).originAPR(blocks);
    }

    function originStakedTotal(uint256 _pid) external view returns (uint256){
        return IStrategy(poolInfo[_pid].strat).originStakedTotal();
    }

    function paused(uint256 _pid) public view returns (bool){
        return IStrategy(poolInfo[_pid].strat).paused();
    }

    function allocPoint(uint256 _pid) public view returns (uint256){
        return poolInfo[_pid].allocPoint;
    }

    function shouldCompound(uint256 _pid) external view returns (bool){
        return !paused(_pid) && tvl(_pid) > 0;
    }
}
