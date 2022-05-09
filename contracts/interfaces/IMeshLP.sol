// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IMeshLP {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function claimReward() external;

    function addETHLiquidityWithLimit(
        uint256 amount,
        uint256 minAmountA,
        uint256 minAmountB,
        address usr
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256 lp
        );

    function addTokenLiquidityWithLimit(
        uint256 amountA,
        uint256 amountB,
        uint256 minAmountA,
        uint256 minAmountB,
        address usr
    )
        external
        returns (
            uint256,
            uint256,
            uint256 lp
        );

    function mining() external view returns (uint256);

    function miningIndex() external view returns (uint256);

    function symbol() external view returns (string memory);

    function estimatePos(address token, uint256 amount) external view returns (uint256);

    function estimateNeg(address token, uint256 amount) external view returns (uint256);

    function getCurrentPool() external view returns (uint256, uint256);

    function userLastIndex(address user) external view returns (uint256);

    function userRewardSum(address) external view returns (uint256);

    function name() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function getTreasury() external view returns (address);

    function router() external view returns (address);
}
