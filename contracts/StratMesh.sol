// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "./helpers/ERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/EnumerableSet.sol";
import "./helpers/Ownable.sol";
import "./interfaces/IMeshLP.sol";
import "./interfaces/IMeshRouter.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
import "./helpers/ReentrancyGuard.sol";
import "./helpers/Pausable.sol";

contract StratMesh is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    bool public isAutoComp; // this vault is purely for staking(true)
    address public wantAddress;
    address public token0Address; //
    address public token1Address; //
    address public earnedAddress; //
    address public uniRouterAddress;
    address public wmaticAddress;
    address public MeshedProtocolAddress;
    address public MSDAddress;
    address public govAddress;
    bool public onlyGov = false;
    uint256 public lastEarn = 0;
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;
    uint256 public platformFee = 150;
    uint256 public constant platformFeeMax = 10000; // 100 = 1%
    uint256 public constant platformFeeUL = 500;
    uint256 public controllerFee = 50;
    uint256 public constant controllerFeeMax = 10000; // 100 = 1%
    uint256 public constant controllerFeeUL = 300;
    uint256 public buyBackRate = 350;
    uint256 public constant buyBackRateMax = 10000; // 100 = 1%
    uint256 public constant buyBackRateUL = 800;
    address public buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    address public rewardsAddress;
    uint256 public entranceFeeFactor = 9990; // < 0.1% entrance fee - goes to pool + prevents front-running
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit
    uint256 public withdrawFeeFactor = 10000; // 0.1% withdraw fee - goes to pool
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit
    uint256 public slippageFactor = 950; // 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;
    address[] public earnedToMSDPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    event SetSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _platformFee,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
    );
    event SetGov(address _govAddress);
    event SetOnlyGov(bool _onlyGov);
    event SetUniRouterAddress(address _uniRouterAddress);
    event SetBuyBackAddress(address _buyBackAddress);
    event SetRewardsAddress(address _rewardsAddress);
    modifier onlyAllowGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    constructor(
        address[] memory _addresses,
        bool _isAutoComp,
        address[] memory _earnedToMSDPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor
    ) public {
        govAddress = _addresses[0];
        MeshedProtocolAddress = _addresses[1];
        MSDAddress = _addresses[2];
        wantAddress = _addresses[3];
        token0Address = _addresses[4];
        token1Address = _addresses[5];
        earnedAddress = _addresses[6];
        isAutoComp = _isAutoComp;
        uniRouterAddress = _addresses[7];
        earnedToMSDPath = _earnedToMSDPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;
        controllerFee = _controllerFee;
        rewardsAddress = _addresses[8];
        buyBackRate = _buyBackRate;
        buyBackAddress = _addresses[9];
        entranceFeeFactor = _entranceFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;
        transferOwnership(MeshedProtocolAddress);
    }

    function deposit(address _userAddress, uint256 _wantAmt) public onlyOwner nonReentrant whenNotPaused returns (uint256) {
        IERC20(wantAddress).safeTransferFrom(address(msg.sender), address(this), _wantAmt);
        uint256 sharesAdded = _wantAmt;
        if (wantLockedTotal > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt.mul(sharesTotal).mul(entranceFeeFactor).div(wantLockedTotal).div(entranceFeeFactorMax);
        }
        sharesTotal = sharesTotal.add(sharesAdded);
        _farm();
        return sharesAdded;
    }

    function farm() public nonReentrant {
        _farm();
    }

    function _farm() internal {
        wantLockedTotal = IERC20(wantAddress).balanceOf(address(this));
    }

    function withdraw(address _userAddress, uint256 _wantAmt) public onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt <= 0");
        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(withdrawFeeFactorMax);
        }
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);
        IERC20(wantAddress).safeTransfer(MeshedProtocolAddress, _wantAmt);
        return sharesRemoved;
    }

    function earn() public whenNotPaused nonReentrant {
        require(isAutoComp, "!isAutoComp");
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }
        IMeshLP(wantAddress).claimReward();
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        if (earnedAmt == 0) {
            return;
        }
        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = buyBack(earnedAmt);
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, earnedAmt);
        if (earnedAddress != token0Address) {
            _safeSwap(
                uniRouterAddress,
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }
        if (earnedAddress != token1Address) {
            _safeSwap(
                uniRouterAddress,
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken1Path,
                address(this),
                block.timestamp.add(600)
            );
        }
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(uniRouterAddress, token0Amt);
            IERC20(token1Address).safeIncreaseAllowance(uniRouterAddress, token1Amt);
            IMeshRouter(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                block.timestamp.add(600)
            );
        }
        lastEarn = block.timestamp;
        _farm();
    }

    function buyBack(uint256 _earnedAmt) internal virtual returns (uint256) {
        if (buyBackRate <= 0) {
            return _earnedAmt;
        }
        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);
        if (earnedAddress == MSDAddress) {
            IERC20(earnedAddress).safeTransfer(buyBackAddress, buyBackAmt);
        } else {
            IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, buyBackAmt);

            _safeSwap(uniRouterAddress, buyBackAmt, slippageFactor, earnedToMSDPath, buyBackAddress, block.timestamp.add(600));
        }
        return _earnedAmt.sub(buyBackAmt);
    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            uint256 totalFees;
            if (controllerFee > 0) {
                uint256 fee = _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                IERC20(earnedAddress).safeTransfer(rewardsAddress, fee);
                totalFees = totalFees.add(fee);
            }
            if (platformFee > 0) {
                uint256 fee = _earnedAmt.mul(platformFee).div(platformFeeMax);
                IERC20(earnedAddress).safeTransfer(govAddress, fee);
                totalFees = totalFees.add(fee);
            }
            _earnedAmt = _earnedAmt.sub(totalFees);
        }
        return _earnedAmt;
    }

    function convertDustToEarned() public virtual whenNotPaused {
        require(isAutoComp, "!isAutoComp");
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(uniRouterAddress, token0Amt);
            _safeSwap(uniRouterAddress, token0Amt, slippageFactor, token0ToEarnedPath, address(this), block.timestamp.add(600));
        }
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(uniRouterAddress, token1Amt);
            _safeSwap(uniRouterAddress, token1Amt, slippageFactor, token1ToEarnedPath, address(this), block.timestamp.add(600));
        }
    }

    function _safeSwap(
        address _uniRouterAddress,
        uint256 _amountIn,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal virtual {
        uint256[] memory amounts = IMeshRouter(_uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];
        IMeshRouter(_uniRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(_slippageFactor).div(1000),
            _path,
            _to,
            _deadline
        );
    }

    function setSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _platformFee,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
    ) public onlyAllowGov {
        require(_entranceFeeFactor >= entranceFeeFactorLL, "_entranceFeeFactor too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "_entranceFeeFactor too high");
        entranceFeeFactor = _entranceFeeFactor;
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "_withdrawFeeFactor too high");
        withdrawFeeFactor = _withdrawFeeFactor;
        require(_platformFee <= platformFeeUL, "_platformFee too low");
        platformFee = _platformFee;
        require(_controllerFee <= controllerFeeUL, "_controllerFee too high");
        controllerFee = _controllerFee;
        require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
        buyBackRate = _buyBackRate;
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        slippageFactor = _slippageFactor;
        emit SetSettings(_entranceFeeFactor, _withdrawFeeFactor, _platformFee, _controllerFee, _buyBackRate, _slippageFactor);
    }

    function pause() public onlyAllowGov {
        _pause();
    }

    function unpause() public onlyAllowGov {
        _unpause();
    }

    function setGov(address _govAddress) public onlyAllowGov {
        govAddress = _govAddress;
    }

    function setOnlyGov(bool _onlyGov) public onlyAllowGov {
        onlyGov = _onlyGov;
    }

    function setUniRouterAddress(address _uniRouterAddress) public onlyAllowGov {
        uniRouterAddress = _uniRouterAddress;
        emit SetUniRouterAddress(_uniRouterAddress);
    }

    function setBuyBackAddress(address _buyBackAddress) public onlyAllowGov {
        buyBackAddress = _buyBackAddress;
        emit SetBuyBackAddress(_buyBackAddress);
    }

    function setRewardsAddress(address _rewardsAddress) public onlyAllowGov {
        rewardsAddress = _rewardsAddress;
        emit SetRewardsAddress(_rewardsAddress);
    }

    function _wrapMATIC() internal virtual {
        uint256 bnbBal = address(this).balance;
        if (bnbBal > 0) {
            IWETH(wmaticAddress).deposit{value: bnbBal}(); // BNB -> WBNB
        }
    }

    function wrapMATIC() public virtual onlyAllowGov {
        _wrapMATIC();
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public onlyAllowGov nonReentrant {
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        require(_token != token0Address, "!safe");
        require(_token != token1Address, "!safe");
        if (_token != address(0)) {
            IERC20(_token).safeTransfer(_to, _amount);
        } else {
            (bool success, ) = (_to).call{value: _amount}("");
            require(success, "Transfer failed.");
        }
    }

    function inCaseDualReward(address[] memory _airdropToEarnedPath, uint256 _airdropAmt) public onlyAllowGov nonReentrant {
        require(_airdropToEarnedPath[_airdropToEarnedPath.length.sub(1)] == earnedAddress, "!earnedToken");
        IERC20(_airdropToEarnedPath[0]).safeIncreaseAllowance(uniRouterAddress, _airdropAmt);
        _safeSwap(uniRouterAddress, _airdropAmt, slippageFactor, _airdropToEarnedPath, address(this), block.timestamp.add(600));
        earn();
    }

    receive() external payable {}
}
