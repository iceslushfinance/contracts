const MasterChefV2 = artifacts.require("MasterChefV2");
const Token = artifacts.require("Token");

module.exports = async function (deployer) {
  const token = await Token.deployed()
  const masterChef = await MasterChefV2.deployed();
  // farms
  await masterChef.add(30000, "0x3576cb8912897b7b825733939c8c3f42b61d8160", 0, 1) // TODO: slush-usdt
  await masterChef.add(30000, "0x1c71e3ca1ed9341a01943f60341491daf161ecc2", 0, 1) // TODO: slush-wavax
  await masterChef.add(30000, "0xfe15c2695f1f920da45c30aae47d11de51007af9", 200, 1) // TODO: add address
  await masterChef.add(30000, "0xed8cbd9f0ce3c6986b22002f03c6475ceb7a6256", 200, 1) // TODO: add address
  // pools
  await masterChef.add(30000, "0x1286BCf476D7C7936Fc6538459f684eF7F989852", 0, 1) // TODO: add address
  await masterChef.add(30000, "0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7", 200, 1) // TODO: add address
  await masterChef.add(30000, "0x50b7545627a5162f82a992c33b87adc75187b218", 200, 1) // TODO: add address
  await masterChef.add(30000, "0x49d5c2bdffac6ce2bfdb6640f4f80f226bc10bab", 200, 1) // TODO: add address
  await masterChef.add(30000, "0xc7198437980c041c805a1edcba50c1ce5db95118", 200, 1) // TODO: add address
  await masterChef.add(30000, "0xd586e7f844cea2f87f50152665bcbc2c279d8d70", 200, 1) // TODO: add address
  await masterChef.add(30000, "0xa7d7079b0fead91f3e65f86e8915cb59c1a4c664", 200, 1) // TODO: add address
  await masterChef.add(30000, "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd", 200, 1) // TODO: add address
  await masterChef.add(30000, "0x59414b3089ce2AF0010e7523Dea7E2b35d776ec7", 200, 1) // TODO: add address
};
