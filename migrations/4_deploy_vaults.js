const TokenStaking = artifacts.require("TokenStaking");
const Token = artifacts.require("EBIToken");

module.exports = async function (deployer) {
  const stakingToken = '0x034D706c3AF9D11F0Ba90d9967947ABEdA7a5758';
  const rewardToken = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174';
  console.log("deploying dividends")
  await deployer.deploy(TokenStaking, stakingToken, rewardToken, 12200, 18843573, 18845373)
};
