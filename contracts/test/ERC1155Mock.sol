pragma solidity ^0.5.0;

import { ERC1155 } from "../ERC1155/ERC1155.sol";

/**
 * @title ERC1155Mock
 * This mock just allows minting for testing purposes
 */
contract ERC1155Mock is ERC1155 {
  function mint(address to, uint256 id, uint256 value, bytes memory data) public {
    _mint(to, id, value, data);
  }
}
