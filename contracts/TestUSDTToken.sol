pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./libs/BEP20.sol";

contract TestUSDT is BEP20('TestUSDT', 'testUSDT') {
    using SafeMath for uint256;

    constructor() {
        _mint(_msgSender(), 100000 ether);
    }
}
