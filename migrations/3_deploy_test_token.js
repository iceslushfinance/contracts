const MasterChefV2 = artifacts.require("MasterChefV2");
const TestUSDT = artifacts.require("TestUSDT");

module.exports = async function (deployer) {
  await deployer.deploy(TestUSDT)
  const token = await TestUSDT.deployed()
};
