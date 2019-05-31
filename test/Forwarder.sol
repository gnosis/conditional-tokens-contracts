pragma solidity ^0.5.0;

contract Forwarder {
    function call(address to, bytes calldata data) external {
        (bool success, bytes memory retData) = to.call(data);
        require(success, string(retData));
    }
}
