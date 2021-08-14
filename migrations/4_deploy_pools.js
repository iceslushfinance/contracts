const MasterChefV2 = artifacts.require("MasterChefV2");
const Token = artifacts.require("EBIToken");

module.exports = async function (deployer) {
  const token = await Token.deployed()
  const masterChef = await MasterChefV2.deployed();
// const masterChef = new web3.eth.Contract(MasterChefV2.abi, "0x17b02ca924f90261c920e59fef812387e5619e9e")

  // Farms
  // await masterChef.add(300, "0x87314ac80724085797b66afc3402a734f0ae8c5b", 0, 1)
  // USDC WETH
  // EBI - MATIC LP (0% fee) (300x)
  await masterChef.add(30000, "0x0", 0, 1) // TODO: add address
  // EBI - USDC LP (0% fee) (300x)
  await masterChef.add(30000, "0x0", 0, 1) // TODO: add address
  // USDC - MATIC LP (4% fee) (35x)
  await masterChef.add(3500, "0x6e7a5fafcec6bb1e78bae2a1f0b612012bf14827", 400, 1)
  // USDC - WETH LP (4% fee) (35x)
  await masterChef.add(3500, "0x853ee4b2a13f8a742d64c8f088be7ba2131f670d", 400, 1) // TODO: add address

  // Pools
  // EBI (0% fee) (80x)
  await masterChef.add(8000, "0x0", 0, 1) // TODO: add address
  // WMATIC (4% fee) (32x)
  await masterChef.add(3200, "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270", 400, 1)
  // WETH (4% fee) (35x)
  await masterChef.add(3500, "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619", 400, 1)
  // WBTC (4% fee) (30x)
  await masterChef.add(3000, "0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6", 400, 1)
  // USDT (4% fee) (35x)
  await masterChef.add(3500, "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", 400, 1)
  // USDC (4% fee) (35x)
  await masterChef.add(3500, "0x2791bca1f2de4661ed88a30c99a7a9449aa84174", 400, 1)
  // DAI (4% fee) (35x)
  await masterChef.add(3500, "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063", 400, 1)
  // LINK (4% fee) (16x)
  await masterChef.add(1600, "0x53e0bca35ec356bd5dddfebbd1fc0fd03fabad39", 400, 1)
  // SUSHI (4% fee) (16x)
  await masterChef.add(1600, "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2", 400, 1)
  // AAVE (4% fee) (16x)
  await masterChef.add(1600, "0xd6df932a45c0f255f85145f286ea0b292b21c90b", 400, 1)
};
