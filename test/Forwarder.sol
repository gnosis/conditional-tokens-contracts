pragma solidity ^0.5.0;

import { ERC1155TokenReceiver } from "../contracts/ERC1155/ERC1155TokenReceiver.sol";

contract Forwarder is ERC1155TokenReceiver {
    function call(address to, bytes calldata data) external {
        (bool success, bytes memory retData) = to.call(data);
        require(success, string(retData));
    }

    function onERC1155Received(
        address /* operator */,
        address /* from */,
        uint256 /* id */,
        uint256 /* value */,
        bytes calldata /* data */
    )
        external
        returns(bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /* operator */,
        address /* from */,
        uint256[] calldata /* ids */,
        uint256[] calldata /* values */,
        bytes calldata /* data */
    )
        external
        returns(bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
