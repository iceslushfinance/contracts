const multicall = artifacts.require("Multicall");
const timelock = artifacts.require("Timelock");

module.exports = async function (deployer) {
  // await deployer.deploy(timelock, "0xd13A5e8C720898D15dD695bE6130f86d5aAAAa72", 10 * 24 * 60 * 60);
  await deployer.deploy(multicall);
};

