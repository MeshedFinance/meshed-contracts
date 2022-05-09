// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IKSP {
    function exchangeKlayPos(
        address token,
        uint256 amount,
        address[] calldata path
    ) external payable;

    function exchangeKctPos(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        address[] memory path
    ) external;

    function exchangeKlayNeg(
        address token,
        uint256 amount,
        address[] memory path
    ) external payable;

    function exchangeKctNeg(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        address[] memory path
    ) external;

    function tokenToPool(address tokenA, address tokenB) external view returns (address);

    function poolExist(address pool) external view returns (bool);

    function pools(uint256 idx) external view returns (address);

    function getPoolCount() external view returns (uint256);

    function getPoolAddress(uint256) external view returns (address);
}
