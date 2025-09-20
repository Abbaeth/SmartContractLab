// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Interface for the factory to get exchange addresses
interface IFactory {
    function getExchange(address token) external view returns (address);
}

contract Exchange is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Address of the ERC20 token and factory
    address public token;
    address public factory;

    // Invariant constants for fee calculation, and fee is 0.3% represented as 997/1000
    uint256 public constant FEE_NUM = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    // Events for logging actions
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount);
    event LiquidityRemoved(address indexed provider, uint256 tokenAmount, uint256 ethAmount);
    event EthToTokenSwap(address indexed buyer, uint256 ethSold, uint256 tokensBought);
    event TokenToEthSwap(address indexed buyer, uint256 tokensSold, uint256 ethBought);
    event TokenToTokenSwap(address indexed buyer, address indexed tokenSold, uint256 tokensSold, address indexed tokenBought, uint256 tokensBought);

    // Constructor to initialize the exchange with a specific ERC20 token and factory address
    constructor(address _token, address _factory) ERC20("Abba Exchange", "AEX-LP") {
        require(_token != address(0), "Exchange: zero token address");
        require(_factory != address(0), "Exchange: zero factory address");
        token = _token;
        factory = _factory;
    }

    // Get current reserves of ETH and the ERC20 token in the exchange
    function getReserves() public view returns (uint256 tokenReserve, uint256 ethReserve) {
        tokenReserve = IERC20(token).balanceOf(address(this));
        ethReserve = address(this).balance;
    }

    // Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getOutputAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
        ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Exchange: invalid reserves");

    // Apply fee and calculate output amount using constant product formula
        uint256 inputAmountWithFee = inputAmount * FEE_NUM;
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * FEE_DENOMINATOR) + inputAmountWithFee;
        return numerator / denominator;
    }

    // Add liquidity to the exchange and mint liquidity tokens
    function addLiquidity(uint256 minLiquidity, uint256 maxTokens) external payable nonReentrant returns (uint256 liquidityMinted) {
      (uint256 tokenReserve, uint256 ethReserve) = getReserves();

        // Initial liquidity provision
        if (totalSupply() == 0) {
            require(msg.value > 0 && maxTokens > 0, "Exchange: insufficient initial liquidity");
            liquidityMinted = msg.value;
            _mint(msg.sender, liquidityMinted);
            IERC20(token).safeTransferFrom(msg.sender, address(this), maxTokens);

            // Emit event for liquidity addition
            emit LiquidityAdded(msg.sender, maxTokens, msg.value);
            return liquidityMinted;

        // Subsequent liquidity provision
        } else {
            require(msg.value > 0, "Exchange: insufficient ETH sent");
            // Calculate required token amount to maintain the pool ratio
            uint256 tokensRequired = (msg.value * tokenReserve) / ethReserve;
            require(tokensRequired <= maxTokens, "Exchange: token amount too low");

            // Calculate liquidity to mint based on contribution
            liquidityMinted = (msg.value * totalSupply()) / ethReserve;
            require(liquidityMinted >= minLiquidity, "Exchange: insufficient liquidity minted");

            // Transfer required tokens from the provider
            IERC20(token).safeTransferFrom(msg.sender, address(this), tokensRequired);
            _mint(msg.sender, liquidityMinted);

            // Emit event for liquidity addition
            emit LiquidityAdded(msg.sender, tokensRequired, msg.value);
            return liquidityMinted;
        }
    }

// Remove liquidity from the exchange and burn liquidity tokens
    function removeLiquidity(uint256 liquidity, uint256 /* minEth */, uint256 /* minTokens */) external nonReentrant returns (uint256 ethAmount, uint256 tokenAmount) {
        require(liquidity > 0, "Exchange: invalid liquidity amount");
        uint256 total = totalSupply();
        require(total > 0, "Exchange: no liquidity");

        // Calculate amounts to withdraw based on share of total liquidity
        ethAmount = (address(this).balance * liquidity) / total;
        tokenAmount = (IERC20(token).balanceOf(address(this)) * liquidity) / total;

        // Burn liquidity tokens
        _burn(msg.sender, liquidity);

        // Transfer ETH and tokens to the liquidity provider
        payable(msg.sender).transfer(ethAmount);
        IERC20(token).safeTransfer(msg.sender, tokenAmount);

        // Emit event for liquidity removal
        emit LiquidityRemoved(msg.sender, tokenAmount, ethAmount);
        return (ethAmount, tokenAmount);
    }

// Swap ETH for tokens 
    function ethToTokenSwap(uint256 minTokens) external payable nonReentrant returns (uint256 tokensBought) {
        // Ensure some ETH is sent
        require(msg.value > 0, "Exchange: insufficient ETH sent");
        // Get current reserves of ETH and tokens, and adjust ETH reserve for incoming ETH
        (uint256 tokenReserve, uint256 ethReserve) = getReserves();
        ethReserve = ethReserve - msg.value;

        // Calculate tokens to be bought
        tokensBought = getOutputAmount(msg.value, ethReserve, tokenReserve);
        require(tokensBought >= minTokens, "Exchange: insufficient output amount");

        // Transfer tokens to the buyer
        IERC20(token).safeTransfer(msg.sender, tokensBought);

        // Emit event for the swap
        emit EthToTokenSwap(msg.sender, msg.value, tokensBought);
        return tokensBought;
    }

// Swap tokens for ETH
    function tokenToEthSwap(uint256 tokensSold, uint256 minEth) external nonReentrant returns (uint256 ethBought) {
        // Ensure some tokens are sold
        require(tokensSold > 0, "Exchange: invalid token amount");
        // Get current reserves of ETH and tokens
        (uint256 tokenReserve, uint256 ethReserve) = getReserves();
        
        // Transfer tokens from the seller to this exchange
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokensSold);

        // Recalculate token reserve after transfer
        uint256 tokenReserveAfter = IERC20(token).balanceOf(address(this));
        uint256 tokensSoldEffective = tokenReserveAfter - tokenReserve;
        require(tokensSoldEffective > 0, "Exchange: token transfer failed");

        // Calculate ETH to be bought
        ethBought = getOutputAmount(tokensSold, tokenReserve, ethReserve);
        require(ethBought >= minEth, "Exchange: insufficient output amount");

        // Transfer ETH to the seller
        payable(msg.sender).transfer(ethBought);

        // Emit event for the swap
        emit TokenToEthSwap(msg.sender, tokensSold, ethBought);
        return ethBought;
    }

// Swap tokens for another token via ETH intermediary
    function tokenToTokenSwap( 
        uint256 tokensSoldAmount, 
        uint256 minTokensBought,
        address tokenSold
        ) external nonReentrant returns (uint256 tokensBought) {
        // Validate input parameters
        require(tokenSold != address(0) && tokenSold != token, "Exchange: invalid token address");
        
        uint256 tokenReserveBefore = IERC20(token).balanceOf(address(this));
        uint256 ethReserveBefore = address(this).balance;

         // Transfer tokens from the user to this exchange
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokensSoldAmount);

        // Recalculate token reserve after transfer
        uint256 tokenReserveAfter = IERC20(token).balanceOf(address(this));

        // Effective tokens sold after transfer
        uint256 tokensSoldEffective = tokenReserveAfter - tokenReserveBefore;

        uint256 ethBought = getOutputAmount(
            tokensSoldEffective, 
            tokenReserveBefore, 
            ethReserveBefore
            );
        
        // Get the exchange address for the target token from the factory
        address exchangeAddress = IFactory(factory).getExchange(tokenSold);
        require(exchangeAddress != address(0), "Exchange: target exchange does not exist");

        // Call ethToTokenSwap on the target exchange to complete the swap
        tokensBought = Exchange(payable(exchangeAddress)).ethToTokenSwap{value: ethBought}(minTokensBought);
        require(tokensBought >= minTokensBought, "Exchange: insufficient output amount");

        // Send the bought tokens to the user
        IERC20(tokenSold).safeTransfer(msg.sender, tokensBought);
        emit TokenToTokenSwap(msg.sender, tokenSold, tokensSoldAmount, tokenSold, tokensBought);

    }

    // Receive function to accept ETH sent directly to the contract
    receive() external payable {
        // Accept ETH sent directly to the contract
    }

    // Fallback function to prevent direct ETH deposits
    fallback() external payable {
        revert("Exchange: do not send ETH directly");

    }

}