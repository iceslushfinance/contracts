// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.0;

interface IStrategy {
    function wantLockedTotal() external view returns (uint256);

    function sharesTotal() external view returns (uint256);

    function lastEarnBlock() external view returns (uint256);

    function lastEarnTimestamp() external view returns (uint256);

    function earn() external;

    function deposit(address _userAddress, uint256 _wantAmt) external returns (uint256);

    function withdraw(address _userAddress, uint256 _wantAmt) external returns (uint256);

    function depositBUSD(address _userAddress, uint256 busdAmount) external returns (uint256);

    function withdrawBUSD(address _userAddress, uint256 shares) external returns (uint256, uint256);

    function tvl() external view returns (uint256);

    function wantTokenValue(uint256 wantAmount) external view returns (uint256);

    function originTVL() external view returns (uint256);

    function rewardTokenValue(uint256 rewardAmount) external view returns (uint256);

    function originRewardsPerBlock() external view returns (uint256);

    function originAPR(uint256 blocks) external view returns (uint256);

    function originStakedTotal() external view returns (uint256);

    function paused() external view returns (bool);
}
