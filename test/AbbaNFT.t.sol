// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "forge-std/Test.sol";
import "../src/AbbaNFT.sol";  // adjust path: src/ or contracts/ depending on your folder

contract AbbaNFTTest is Test, IERC721Receiver {
    AbbaNFT nft;
    address owner = address(this); // test contract will deploy it
    address user1 = address(0x1);

    function setUp() public {
        nft = new AbbaNFT(); // deploy NFT
    }

    function testMint() public {
        nft.mint(user1);
        assertEq(nft.ownerOf(1), user1, "Mint failed or wrong owner");
    }

    function testMaxSupply() public {
        for (uint256 i = 1; i < 5555; i++) {
            nft.mint(user1);
        }
        vm.expectRevert("Max supply reached");
        nft.mint(user1); // should revert on 5556th mint
    }

    function testOnlyOwnerCanPause() public {
        vm.expectRevert(); // should fail if non-owner calls
        vm.prank(user1);
        nft.pause();

        // owner can pause
        nft.pause();
        assertTrue(nft.paused(), "Pause failed");
    }

    function testPauseAndUnpause() public {
        nft.pause();
        assertTrue(nft.paused(), "Pause not set");

        nft.unpause();
        assertFalse(nft.paused(), "Unpause not set");
    }

    function testTransferWhilePausedReverts() public {
        nft.mint(owner);
        nft.pause();
        vm.expectRevert();
        nft.transferFrom(owner, user1, 1);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

