pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./libs/BEP20.sol";

contract Token is BEP20('Test', 'tst1') {
    using SafeMath for uint256;

    // Transfer tax rate in basis points. (default 3%)
    uint16 public transferTaxRate = 300;
    // Burn rate % of transfer tax. (default 25% x 4% = 1% of total amount).
    uint16 public burnRate = 33;
    // Max transfer tax rate: 10%.
    uint16 public constant MAXIMUM_TRANSFER_TAX_RATE = 300;
    // Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Automatic swap and liquify enabled
    bool public swapAndLiquifyEnabled = false;
    // Min amount to liquify. (default 25 Token)
    uint256 public minAmountToLiquify = 25 ether;
    // The swap router.
    IUniswapV2Router02 public constant swapRouter = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    // The trading pair
    address public swapPair;
    // In swap and liquify
    bool private _inSwapAndLiquify;
    // Liquidity address, if not set it will be operator, timelock after start
    address public liquidityAddress = 0x000000000000000000000000000000000000dEaD;


    // The operator can only update the transfer tax rate
    address private _operator;

    // Events
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event TransferTaxRateUpdated(address indexed operator, uint256 previousRate, uint256 newRate);
    event BurnRateUpdated(address indexed operator, uint256 previousRate, uint256 newRate);
    event SwapAndLiquifyEnabledUpdated(address indexed operator, bool enabled);
    event MinAmountToLiquifyUpdated(address indexed operator, uint256 previousAmount, uint256 newAmount);
    event SwapRouterUpdated(address indexed operator, address indexed router, address indexed pair);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    modifier lockTheSwap {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    modifier transferTaxFree {
        uint16 _transferTaxRate = transferTaxRate;
        transferTaxRate = 0;
        _;
        transferTaxRate = _transferTaxRate;
    }

    /**
     * @notice Constructs the Token contract.
     */
    constructor() {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev overrides transfer function to meet tokenomics of TMGO
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // swap and liquify
        if (
            swapAndLiquifyEnabled == true &&
            _inSwapAndLiquify == false &&
            address(swapRouter) != address(0) &&
            swapPair != address(0) &&
            sender != swapPair &&
            sender != owner()
        ) {
            swapAndLiquify();
        }

        if (recipient == BURN_ADDRESS || transferTaxRate == 0) {
            super._transfer(sender, recipient, amount);
        } else {
            // default tax is 5% of every transfer
            uint256 taxAmount = amount.mul(transferTaxRate).div(10000);
            uint256 burnAmount = taxAmount.mul(burnRate).div(100);
            uint256 liquidityAmount = taxAmount.sub(burnAmount);
            require(taxAmount == burnAmount + liquidityAmount, "TMGO::transfer: Burn value invalid");

            // default 95% of transfer sent to recipient
            uint256 sendAmount = amount.sub(taxAmount);
            require(amount == sendAmount + taxAmount, "TMGO::transfer: Tax value invalid");

            super._transfer(sender, BURN_ADDRESS, burnAmount);
            super._transfer(sender, address(this), liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

    /// @dev Swap and liquify
    function swapAndLiquify() private lockTheSwap transferTaxFree {
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= minAmountToLiquify) {
            // only min amount to liquify
            uint256 liquifyAmount = minAmountToLiquify;

            // split the liquify amount into halves
            uint256 half = liquifyAmount.div(2);
            uint256 otherHalf = liquifyAmount.sub(half);

            // capture the contract's current ETH balance.
            // this is so that we can capture exactly the amount of ETH that the
            // swap creates, and not make the liquidity event include any ETH that
            // has been manually sent to the contract
            uint256 initialBalance = address(this).balance;

            // swap tokens for ETH
            swapTokensForEth(half);

            // how much ETH did we just swap into?
            uint256 newBalance = address(this).balance.sub(initialBalance);

            // add liquidity
            addLiquidity(otherHalf, newBalance);

            emit SwapAndLiquify(half, newBalance, otherHalf);
        }
    }

    /// @dev Swap tokens for eth
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the swap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = swapRouter.WETH();

        _approve(address(this), address(swapRouter), tokenAmount);

        // make the swap
        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Add liquidity
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(swapRouter), tokenAmount);
        address liquidityAddressTarget = operator();
        if (liquidityAddress != BURN_ADDRESS) {
            liquidityAddressTarget = liquidityAddress;
        }
        // add the liquidity
        swapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityAddressTarget,
            block.timestamp
        );
    }

    // To receive MATIC from swapRouter when swapping
    receive() external payable {}

    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current operator.
     */
    function updateTransferTaxRate(uint16 _transferTaxRate) public onlyOperator {
        require(_transferTaxRate <= MAXIMUM_TRANSFER_TAX_RATE, "TMGO::updateTransferTaxRate: Transfer tax rate must not exceed the maximum rate.");
        emit TransferTaxRateUpdated(msg.sender, transferTaxRate, _transferTaxRate);
        transferTaxRate = _transferTaxRate;
    }

    /**
     * @dev Update the burn rate.
     * Can only be called by the current operator.
     */
    function updateBurnRate(uint16 _burnRate) public onlyOperator {
        require(_burnRate <= 100, "TMGO::updateBurnRate: Burn rate must not exceed the maximum rate.");
        emit BurnRateUpdated(msg.sender, burnRate, _burnRate);
        burnRate = _burnRate;
    }


    /**
     * @dev Update the min amount to liquify.
     * Can only be called by the current operator.
     */
    function updateMinAmountToLiquify(uint256 _minAmount) public onlyOperator {
        emit MinAmountToLiquifyUpdated(msg.sender, minAmountToLiquify, _minAmount);
        minAmountToLiquify = _minAmount;
    }

    /**
     * @dev Update the swapAndLiquifyEnabled.
     * Can only be called by the current operator.
     */
    function updateSwapAndLiquifyEnabled(bool _enabled) public onlyOperator {
        emit SwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
        swapAndLiquifyEnabled = _enabled;
    }

    function setLiquidityAddress(address _liquidityAddress) public onlyOperator {
        liquidityAddress = _liquidityAddress;
    }

    function setSwapPair() public onlyOperator {
        swapPair = IUniswapV2Factory(swapRouter.factory()).getPair(address(this), swapRouter.WETH());
        require(swapPair != address(0), "TMGO::updateSwapRouter: Invalid pair address. Check if liquidity was added");
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) public onlyOperator {
        require(newOperator != address(0), "TMGO::transferOperator: new operator is the zero address");
        emit OperatorTransferred(_operator, newOperator);
        _operator = newOperator;
    }

    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
