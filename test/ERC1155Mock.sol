// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.7.0 <0.9.0;

import { ERC1155 } from "../contracts/ERC1155/ERC1155.sol";

/**
 * @title ERC1155Mock
 * This mock just allows minting for testing purposes
 */
contract ERC1155Mock is ERC1155 {
  function mint(address to, uint256 id, uint256 value, bytes memory data) public {
    _mint(to, id, value, data);
  }
}
