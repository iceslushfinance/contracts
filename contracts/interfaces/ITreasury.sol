// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.0;

interface ITreasury {
    function updateEmissionRate() external returns (uint256 emissionRate);
    function mintGooseDollar(uint256 dollarAmount) external returns (uint256 mintAmount);
    function borrow(uint256 dollarAmount) external returns (bool);
    function settle(uint256 settleAmount, uint256 debtAmount) external returns (bool);
    function income(uint256 dollarAmount) external;
}
