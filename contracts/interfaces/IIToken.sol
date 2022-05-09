// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IIToken {
    function exchangeRateStored() external view returns (uint256);

    function decimals() external view returns (uint8);

    function poolTotalBorrows(address) external view returns (uint256 principal, uint256 interestIndex);

    function getCash() external view returns (uint256);

    function reserveFactor() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function singlePoolFactory() external view returns (address);

    function userRewardSum(address _user) external view returns (uint256);

    function borrowBalancePoolTotal(address poolAddress) external view returns (uint256);

    function mining() external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    function borrowBalanceStored(address account, address poolAddress) external view returns (uint256);

    function miningIndex() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function entered() external view returns (bool);

    function borrowIndex() external view returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function lastMined() external view returns (uint256);

    function borrowBalanceInfo(address account, address poolAddress) external view returns (uint256, uint256);

    function userLastIndex(address _user) external view returns (uint256);

    function claimReward() external;

    function depositKct(uint256 _amount) external;

    function depositKlay() external payable;

    function withdraw(uint256 _amount) external;

    function token() external view returns (address);
}
