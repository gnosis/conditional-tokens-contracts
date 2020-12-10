// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.1;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract MockCoin is ERC20 {
    constructor () ERC20("Mock", "MCK") { }

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }
}
