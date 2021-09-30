const MasterChefV2 = artifacts.require("MasterChefV2");
const Token = artifacts.require("Token");

module.exports = async function (deployer) {
  await deployer.deploy(Token)
  const token = await Token.deployed()

  const devAddr = "0xC8ad39418043AB46737eD0055E0a9c7E85cf6238"

  const startBlock = 19250416;

  await deployer.deploy(
    MasterChefV2,
    token.address,
    devAddr,
    devAddr,
    "70000000000000000", // TODO: 0.07
    startBlock
  );
  const masterChef = await MasterChefV2.deployed();
  // mint for developer
  await token.mint(devAddr, "200000000000000000000")
  // transfer ownership to masterchef
  await token.transferOwnership(masterChef.address)
};
