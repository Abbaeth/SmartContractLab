// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AbbaETH.sol";  // adjust path: src/ or contracts/ depending on your folder

contract AbbaETHTest is Test {
    AbbaETH token;
    address owner = address(this); // test contract will deploy it
    address user1 = address(0x1);

    function setUp() public {
        token = new AbbaETH(); // deploy token
    }

    function testInitialSupply() public {
        uint256 expected = 21000000000 * 10 ** token.decimals();
        assertEq(token.totalSupply(), expected, "Initial supply mismatch");
        assertEq(token.balanceOf(owner), expected, "Owner should have all tokens");
    }

    function testBurn() public {
        uint256 burnAmount = 1000 * 10 ** token.decimals();
        token.burn(burnAmount);
        assertEq(
            token.balanceOf(owner),
            token.totalSupply(),
            "Burn did not reduce balance"
        );
    }

    function testOnlyOwnerCanPause() public {
        vm.expectRevert(); // should fail if non-owner calls
        vm.prank(user1);
        token.pause();

        // owner can pause
        token.pause();
        assertTrue(token.paused(), "Pause failed");
    }

    function testPauseAndUnpause() public {
        token.pause();
        assertTrue(token.paused(), "Pause not set");

        token.unpause();
        assertFalse(token.paused(), "Unpause not set");
    }

    function testTransferWhilePausedReverts() public {
        token.pause();
        vm.expectRevert();
        token.transfer(user1, 1000);
    }
}