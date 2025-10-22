// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockDoc is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Dollar On Chain", "DOC") Ownable() {
        _mint(msg.sender, 1_000_000 ether); // Mint 1M DOC for testing
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
