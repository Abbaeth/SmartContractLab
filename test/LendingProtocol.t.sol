// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockPriceFeed} from "../src/MockPriceFeed.sol";

// Test contract for LendingProtocol
contract LendingProtocolTest is Test {
    LendingProtocol protocol;

    MockERC20 collateralToken;
    MockERC20 borrowToken;
    MockPriceFeed collateralFeed;
    MockPriceFeed borrowFeed;

    address user1 = address(1);
    address liquidator = address(2);

    function setUp() public {
        // Deploy mock tokens
        collateralToken = new MockERC20("CollateralToken", "COL");
        borrowToken = new MockERC20("BorrowToken", "BOR");

        // Deploy mock price feeds
        collateralFeed = new MockPriceFeed(2000e8, 8); // 1 COL = $2000
        borrowFeed = new MockPriceFeed(1e8, 8);        // 1 BOR = $1

        // Deploy protocol
        protocol = new LendingProtocol(
            address(collateralToken),
            address(borrowToken),
            address(collateralFeed),
            address(borrowFeed)
        );

        // Fund users + protocol
        collateralToken.mint(user1, 10 ether); // 10 COL for user1
        borrowToken.mint(address(protocol), 10000 ether); // liquidity pool
    }

    function testDepositCollateral() public {
        vm.startPrank(user1);

        collateralToken.approve(address(protocol), 1 ether);
        protocol.depositCollateral(1 ether);

        vm.stopPrank();

        assertEq(protocol.collateralBalances(user1), 1 ether, "User should have 1 COL collateral");
    }

    function testBorrowWithinLimits() public {
    vm.startPrank(user1);

    collateralToken.approve(address(protocol), 2e18);
    protocol.depositCollateral(2e18); // $4000 worth of collateral

    protocol.borrow(1000e18); // Well within 75% of $4000 ($3000)

    vm.stopPrank();

    uint256 debt = protocol.borrowBalances(user1);
    assertEq(debt, 1000e18, "Borrow balance should be 1000 BOR");
}

function testLiquidationWhenHFBelow1() public {
    vm.startPrank(user1);

    // Deposit 1 COL worth $2000
    collateralToken.approve(address(protocol), 1e18);
    protocol.depositCollateral(1e18);

    // Borrow close to max
    protocol.borrow(1499e18);
    vm.stopPrank();

    // Simulate price drop
    collateralFeed.setPrice(1000e8);

    // Liquidator
    vm.startPrank(address(2));
    borrowToken.mint(address(2), 1500e18);

    // Get max repayable according to close factor
    uint256 debt = protocol.borrowBalances(user1);
    uint256 maxClose = (debt * protocol.CLOSE_FACTOR()) / 1e18;

    borrowToken.approve(address(protocol), maxClose);
    protocol.liquidate(user1, maxClose);

    vm.stopPrank();

    // Assert liquidation effects
    assertLt(protocol.borrowBalances(user1), debt, "Debt should decrease after liquidation");
    assertLt(protocol.collateralBalances(user1), 1e18, "Collateral should decrease after liquidation");
    }

}
