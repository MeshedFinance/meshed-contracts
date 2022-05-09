// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IKSLP {
    function tokenA() external view returns (address);

    function tokenB() external view returns (address);

    function claimReward() external;

    function estimatePos(address token, uint256 amount) external view returns (uint256);

    function estimateNeg(address token, uint256 amount) external view returns (uint256);

    function addKlayLiquidity(uint256 amount) external payable;

    function addKlayLiquidityWithLimit(
        uint256 amount,
        uint256 minAmountA,
        uint256 minAmountB
    ) external payable;

    function addKctLiquidity(uint256 amountA, uint256 amountB) external;

    function removeLiquidity(uint256 amount) external;

    function getCurrentPool() external view returns (uint256, uint256);

    function addKctLiquidityWithLimit(
        uint256 amountA,
        uint256 amountB,
        uint256 minAmountA,
        uint256 minAmountB
    ) external;

    function userLastIndex(address user) external view returns (uint256);

    function miningIndex() external view returns (uint256);

    function userRewardSum(address) external view returns (uint256);

    function mining() external view returns (uint256);

    function name() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function getTreasury() external view returns (address);
}
