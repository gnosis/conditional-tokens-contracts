// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.7.0 <0.9.0;

import "./IERC1155TokenReceiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";

abstract contract ERC1155TokenReceiver is ERC165Storage, IERC1155TokenReceiver {
    constructor()  {
        _registerInterface(
            ERC1155TokenReceiver(address(0)).onERC1155Received.selector ^
            ERC1155TokenReceiver(address(0)).onERC1155BatchReceived.selector
        );
    }
}
