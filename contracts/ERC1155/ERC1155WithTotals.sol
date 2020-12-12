pragma solidity ^0.5.1;
import { ERC1155 } from "./ERC1155.sol";

contract ERC1155WithTotals is ERC1155 {
    /// Mapping (token => total).
    mapping(uint256 => uint256) private totalBalances;

    function totalBalanceOf(uint256 id) public view returns (uint256) {
        return totalBalances[id];
    }

    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal {
        require(to != address(0), "ERC1155: mint to the zero address");

        _doMint(to, id, value);
        emit TransferSingle(msg.sender, address(0), to, id, value);

        _doSafeTransferAcceptanceCheck(msg.sender, address(0), to, id, value, data);
    }

    function _batchMint(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        require(to != address(0), "ERC1155: batch mint to the zero address");
        require(ids.length == values.length, "ERC1155: IDs and values must have same lengths");

        for(uint i = 0; i < ids.length; i++) {
            _doMint(to, ids[i], values[i]);
        }

        emit TransferBatch(msg.sender, address(0), to, ids, values);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, address(0), to, ids, values, data);
    }

    function _burn(address owner, uint256 id, uint256 value) internal {
        _doBurn(owner, id, value);
        emit TransferSingle(msg.sender, owner, address(0), id, value);
    }

    function _batchBurn(address owner, uint256[] memory ids, uint256[] memory values) internal {
        require(ids.length == values.length, "ERC1155: IDs and values must have same lengths");

        for(uint i = 0; i < ids.length; i++) {
            _doBurn(owner, ids[i], values[i]);
        }

        emit TransferBatch(msg.sender, owner, address(0), ids, values);
    }

    function _doMint(address to, uint256 id, uint256 value) private {
        totalBalances[id] = totalBalances[id].add(_balances[id][to]);
        _balances[id][to] = value + _balances[id][to]; // The previous didn't overflow, therefore this doesn't overflow.
    }

    function _doBurn(address to, uint256 id, uint256 value) private {
        _balances[id][to] = _balances[id][to].sub(value);
        totalBalances[id] = totalBalances[id] - _balances[id][to]; // The previous didn't overflow, therefore this doesn't overflow.
    }
}