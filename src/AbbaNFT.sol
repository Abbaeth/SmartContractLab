// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// Import OpenZeppelin Contracts
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Pausable} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Define the AbbaNFT contract
contract AbbaNFT is ERC721, ERC721Pausable, Ownable {

// Token ID tracker and max supply
    uint256 private nextTokenId = 1;
    uint256 public constant MAX_SUPPLY = 5555;

// Constructor to initialize the NFT with name and symbol
    constructor() ERC721("AbbaNFT", "ANFT") Ownable(msg.sender) {}

// Function to pause all token transfers
    function pause() public onlyOwner {
        _pause();
    }

// Function to unpause all token transfers
    function unpause() public onlyOwner {
        _unpause();
    }

// Function to mint new NFTs, only callable by the owner
    function mint(address to) public onlyOwner {
        require(nextTokenId < MAX_SUPPLY, "Max supply reached");
        uint256 tokenId = nextTokenId;
        nextTokenId++;
        _safeMint(to, tokenId);
    }

// Override the _beforeTokenTransfer function to include pausability checks
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}