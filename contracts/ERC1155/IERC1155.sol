// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
    @title ERC-1155 Multi Token Standard basic interface
    @dev See https://eips.ethereum.org/EIPS/eip-1155
 */
interface IERC1155 is IERC165 {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event URI(string value, uint256 indexed id);

    function balanceOf(address owner, uint256 id) external view returns (uint256);

    function balanceOfBatch(address[] memory owners, uint256[] memory ids) external view returns (uint256[] memory);

    function setApprovalForAll(address operator, bool approved) external ;

    function isApprovedForAll(address owner, address operator) external  view returns (bool);

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external ;

    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external ;
}
