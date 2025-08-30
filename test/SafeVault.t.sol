// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/SafeVault.sol";

contract SafeVaultTest is Test {
    SafeVault vault;
    address user1 = address(1);
    address user2 = address(2);

    function setUp() public {
        vault = new SafeVault();

        // give test users ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 5 ether);
    }

    function testDeposit() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        assertEq(vault.balanceOf(user1), 2 ether, "User1 balance should be 2 ETH");
        assertEq(address(vault).balance, 2 ether, "Vault contract should hold 2 ETH");
    }

    function testWithdraw() public {
        // user1 deposits 3 ETH
        vm.prank(user1);
        vault.deposit{value: 3 ether}();

        // user1 withdraws 1 ETH
        vm.prank(user1);
        vault.withdraw(1 ether);

        assertEq(vault.balanceOf(user1), 2 ether, "User1 should have 2 ETH left in vault");
        assertEq(address(vault).balance, 2 ether, "Vault should hold 2 ETH");
    }

    function test_RevertWithdrawWithoutDeposit() public {
    vm.prank(user2);
    vm.expectRevert("Insufficient balance");
    vault.withdraw(1 ether);
}

function test_RevertWithdrawMoreThanBalance() public {
    vm.prank(user1);
    vault.deposit{value: 1 ether}();

    vm.prank(user1);
    vm.expectRevert("Insufficient balance");
    vault.withdraw(2 ether);
}

    function testEvents() public {
        vm.expectEmit(true, false, false, true);
        emit SafeVault.Deposited(user1, 1 ether);

        vm.prank(user1);
        vault.deposit{value: 1 ether}();
    }
}