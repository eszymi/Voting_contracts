// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PermitToken is ERC20, Ownable {
    address delegater;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mintPerUser(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        for (uint256 i; i < users.length; ++i) {
            _mint(users[i], amounts[i]);
        }
    }

    function mint(address user, uint256 amount) external onlyOwner {
        _mint(user, amount);
    }

    function setDelegater(address _delegater) external onlyOwner {
        require(delegater == address(0), "Delegater is set");
        delegater = _delegater;
    }

    function approveForDelegate(address from,  uint256 amount) external {
        require(msg.sender == delegater, "You're not delegater");
        _approve(from, delegater, amount);
    }
}
