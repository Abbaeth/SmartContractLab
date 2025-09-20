// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Exchange} from "./Exchange.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyFactory is Ownable {

// Mapping from token address to its exchange address
    mapping(address => address) public getExchange;                                    
    address[] public allExchanges;                  

// Event emitted when a new exchange is created  
    event ExchangeCreated(address indexed token, address exchange, uint);  

// Factory constructor setting the deployer as the owner
    constructor() Ownable(msg.sender) {

    }                      

// Create a new exchange for a given ERC20 token
    function createExchange(address token)
    external 
    onlyOwner 
    returns (address exchange) 
    {
// Validate the token address and ensure no existing exchange
        IERC20 erc20 = IERC20(token);
        require(erc20.totalSupply() >= 0, "Not a valid ERC20 token"); 
        
        require(token != address(0), "Invalid token address");          
        require(getExchange[token] == address(0), "Exchange already exists");    

// Deploy a new Exchange contract
        Exchange ex = new Exchange(token, address(this));                    
        exchange = address(ex);  

// Store the new exchange in mappings and arrays
        getExchange[token] = exchange;                               
        allExchanges.push(exchange);  

// Emit event for the new exchange creation
        emit ExchangeCreated(token, exchange, allExchanges.length);  
    }

// Return the total number of exchanges created
    function allExchangesLength() external view returns (uint) {
        return allExchanges.length;                                  
    }
}