// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Exchange.sol";
import "../src/MyFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple mock token
contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract ExchangeTest is Test {
    Exchange exchange;
    MyFactory factory;
    Token token;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        factory = new MyFactory();
        token = new Token("Test Token", "TT", 1_000_000 ether);

        // Create exchange for token
        address exchangeAddress = factory.createExchange(address(token));
        exchange = Exchange(payable(exchangeAddress));

        // Give users ETH and tokens
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        token.transfer(user1, 1_000 ether);
        token.transfer(user2, 1_000 ether);

        // Approvals
        vm.startPrank(user1);
        token.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(exchange), type(uint256).max);
        vm.stopPrank();
    }

    // --- Liquidity ---

    function testAddLiquidity() public {
        vm.startPrank(user1);

        // Your original addLiquidity call
        exchange.addLiquidity{value: 10 ether}(100 ether);

        // Use getReserves() instead of getReserve()
        (uint tokenReserve, uint ethReserve) = exchange.getReserves();

        assertEq(tokenReserve, 100 ether, "Token reserve mismatch");
        assertEq(ethReserve, 10 ether, "ETH reserve mismatch");

        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        vm.startPrank(user1);
        exchange.addLiquidity{value: 10 ether}(100 ether);

        uint liquidity = exchange.balanceOf(user1);

        exchange.removeLiquidity(liquidity / 2, 1, 1);

        assertGt(token.balanceOf(user1), 900 ether, "Tokens not returned");
        assertGt(user1.balance, 95 ether, "ETH not returned");

        vm.stopPrank();
    }

    // --- Swaps ---

    function testEthToTokenSwap() public {
        vm.startPrank(user1);
        exchange.addLiquidity{value: 10 ether}(100 ether);
        vm.stopPrank();

        vm.startPrank(user2);

        uint beforeBal = token.balanceOf(user2);

        exchange.ethToTokenSwap{value: 1 ether}(1);

        uint afterBal = token.balanceOf(user2);
        assertGt(afterBal, beforeBal, "Swap did not give tokens");

        vm.stopPrank();
    }

    function testTokenToEthSwap() public {
        vm.startPrank(user1);
        exchange.addLiquidity{value: 10 ether}(100 ether);
        vm.stopPrank();

        vm.startPrank(user2);

        uint beforeBal = user2.balance;

        exchange.tokenToEthSwap(10 ether, 1);

        uint afterBal = user2.balance;
        assertGt(afterBal, beforeBal, "Swap did not give ETH");

        vm.stopPrank();
    }
}
