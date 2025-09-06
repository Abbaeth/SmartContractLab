// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import "../src/AbbaStaking.sol";
import "../src/MockERC20.sol";
import "forge-std/Test.sol";

// Test contract for AbbaStaking
contract AbbaStakingTest is Test {
    AbbaStaking staking;
    MockERC20 token;

// Address variables for testing
    address owner = address(this); // test contract will deploy it
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        token = new MockERC20("TestToken", "TTK", 18);

// Deploy the staking contract
        staking = new AbbaStaking(address(token), address(token), owner);

// Mint some tokens for users
        token.mint(address(staking), 10000 ether); // fund staking contract with rewards
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);

// Users approve the staking contract to spend their tokens
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }
// Test staking functionality
    function testStake() public {
    uint256 stakeAmount = 100 ether;

    vm.prank(user1);
    staking.stake(stakeAmount, 30 days); // pick lock period

    assertEq(staking.balanceOf(user1), stakeAmount, "Stake balance mismatch");
    assertEq(staking.totalSupply(), stakeAmount, "Total supply mismatch");
}
// Test reward accumulation over time
    function testEarned() public {
    uint256 stakeAmount = 100 ether;

    vm.prank(user1);
    staking.stake(stakeAmount, 30 days);

    // Fast forward time by 1 day
    vm.warp(block.timestamp + 1 days);

    uint256 earned = staking.earned(user1);
    assertGt(earned, 0, "User should have earned some rewards");
    vm.stopPrank();
}

// Test withdrawing staked tokens after lock period
   function testWithdrawEarly() public {
    uint256 stakeAmount = 100 ether;

    vm.startPrank(user1);
    staking.stake(stakeAmount, 30 days);

// Withdraw before lock ends
    vm.warp(block.timestamp + 10 days);
    staking.withdraw(stakeAmount);

    uint256 userBalance = token.balanceOf(user1);
    uint256 contractBalance = token.balanceOf(address(staking));

// Calculate expected payout after 5% fee
    uint256 expectedPayout = stakeAmount - (stakeAmount * 50 / 1000);

// Assertions
assertEq(userBalance, 1000 ether - stakeAmount + expectedPayout, "User balance incorrect after fee");
assertEq(token.balanceOf(staking.feeRecipient()), stakeAmount * 50 / 1000, "Fee recipient did not get fee");
assertEq(contractBalance, 10000 ether, "Contract reward balance should be unchanged");

    vm.stopPrank();
}

// Test withdrawing staked tokens after lock period
function testWithdrawAfterLock() public {
    uint256 stakeAmount = 100 ether;

    vm.startPrank(user1);
    staking.stake(stakeAmount, 30 days);

    // Fast forward beyond lock
    vm.warp(block.timestamp + 31 days);
    staking.withdraw(stakeAmount);

    assertEq(token.balanceOf(user1), 1000 ether, "User should get full stake back");

    vm.stopPrank();
}

// Test claiming rewards
function testGetReward() public {
    uint256 stakeAmount = 100 ether;

    vm.startPrank(user1);
    staking.stake(stakeAmount, 30 days);

    // Warp forward in time
    vm.warp(block.timestamp + 7 days);

    uint256 earned = staking.earned(user1);
    assertGt(earned, 0, "User should have earned rewards");

    staking.getReward();
    assertEq(staking.earned(user1), 0, "Rewards should reset after claim");
    vm.stopPrank();
}

// Test exit function
function testExit() public {
    uint256 stakeAmount = 100 ether;

    vm.startPrank(user1);
    staking.stake(stakeAmount, 30 days);

    // Warp forward in time
    vm.warp(block.timestamp + 31 days);

    staking.exit();

    uint256 finalBalance = token.balanceOf(user1);

// User should have their stake + rewards
    assertGt(finalBalance, 1000 ether, "User should get stake + rewards back");

// Calculate rewards received
    uint256 rewards = finalBalance - 1000 ether;
    assertGt(rewards, 0, "User should have received some rewards");

    vm.stopPrank();
}

// Test pausing and unpausing the contract
function testPauseUnpause() public {
    staking.pause();
    assertTrue(staking.paused(), "Contract should be paused");

    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
    staking.stake(100 ether, 30 days);

    staking.unpause();
    assertFalse(staking.paused(), "Contract should be unpaused");

    vm.prank(user1);
    staking.stake(100 ether, 30 days);
    assertEq(staking.balanceOf(user1), 100 ether, "Stake balance mismatch after unpause");
}

}


