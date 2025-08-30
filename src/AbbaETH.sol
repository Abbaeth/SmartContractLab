// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// Import OpenZeppelin Contracts
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Define the AbbaETH contract
contract AbbaETH is ERC20, ERC20Pausable, Ownable {

// Constructor to initialize the token with name, symbol, and initial supply
    constructor() ERC20("AbbaETH", "AETH") Ownable(msg.sender) {
        _mint(msg.sender, 21000000000 * 10 ** decimals());

    }

// Function to pause all token transfers
    function pause() public onlyOwner {
        _pause();
    }

// Function to unpause all token transfers
    function unpause() public onlyOwner {
        _unpause();
    }

// Function to burn tokens from the caller's account by the holder
    function burn(uint256 amount) public whenNotPaused {
        _burn(msg.sender, amount);
    }

// Override the _update function to include pausability checks
    function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Pausable)
{
    super._update(from, to, value);
}

}