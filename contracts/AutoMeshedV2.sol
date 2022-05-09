// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "./helpers/ERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/EnumerableSet.sol";
import "./helpers/Ownable.sol";
import "./helpers/ReentrancyGuard.sol";
import "./MeshedToken.sol";
import "./interfaces/IStrategy.sol";

contract AutoMeshedV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }
    struct PoolInfo {
        IERC20 want; // Address of the want token.
        uint256 allocPoint; // How many allocation points assigned to this pool. MSD to distribute per block.
        uint256 lastRewardBlock; // Last block number that MSD distribution occurs.
        uint256 accMSDPerShare; // Accumulated MSD per share, times 1e12. See below.
        address strat; // Strategy address that will MSD compound want tokens
    }
    address public MSD;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    bool public initialized = false;
    uint256 public MSDMaxSupply = 438_000e18; // 2 years
    uint256 public MSDPerBlock = 1e16; // 0.01 MSD per Block
    uint256 public startBlock = 28069363;
    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function initialize(address _MSD) public onlyOwner {
        require(!initialized, "initialized");
        require(_MSD != address(0), "!safeMSD");
        require(block.number < startBlock, "late");
        MSD = _MSD;
        initialized = true;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _strat
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({want: _want, allocPoint: _allocPoint, lastRewardBlock: lastRewardBlock, accMSDPerShare: 0, strat: _strat})
        );
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (IERC20(MSD).totalSupply() >= MSDMaxSupply) {
            return 0;
        }
        return _to.sub(_from);
    }

    function pendingMSD(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMSDPerShare = pool.accMSDPerShare;
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 MSDReward = multiplier.mul(MSDPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accMSDPerShare = accMSDPerShare.add(MSDReward.mul(1e12).div(sharesTotal));
        }
        return user.shares.mul(accMSDPerShare).div(1e12).sub(user.rewardDebt);
    }

    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

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
        uint256 MSDReward = multiplier.mul(MSDPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        MeshedToken(MSD).mint(address(this), MSDReward);

        pool.accMSDPerShare = pool.accMSDPerShare.add(MSDReward.mul(1e12).div(sharesTotal));
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.shares > 0) {
            uint256 pending = user.shares.mul(pool.accMSDPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeMSDTransfer(msg.sender, pending);
            }
        }
        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(address(msg.sender), address(this), _wantAmt);

            pool.want.approve(pool.strat, _wantAmt.add(pool.want.allowance(address(this), pool.strat)));
            uint256 sharesAdded = IStrategy(poolInfo[_pid].strat).deposit(msg.sender, _wantAmt);
            user.shares = user.shares.add(sharesAdded);
        }
        user.rewardDebt = user.shares.mul(pool.accMSDPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    function depositAll(uint256 _pid) public nonReentrant {
        deposit(_pid, uint256(-1));
    }

    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();
        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");
        uint256 pending = user.shares.mul(pool.accMSDPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeMSDTransfer(msg.sender, pending);
        }
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);
            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }
            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(msg.sender), _wantAmt);
        }
        user.rewardDebt = user.shares.mul(pool.accMSDPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, amount);
        pool.want.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    function harvestAll() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            withdraw(pid, 0);
        }
    }

    function safeMSDTransfer(address _to, uint256 _MSDAmt) internal {
        uint256 MSDbal = IERC20(MSD).balanceOf(address(this));
        if (_MSDAmt > MSDbal) {
            IERC20(MSD).transfer(_to, MSDbal);
        } else {
            IERC20(MSD).transfer(_to, _MSDAmt);
        }
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public onlyOwner {
        require(_token != MSD, "!safe");
        IERC20(_token).transfer(msg.sender, _amount);
    }
}
