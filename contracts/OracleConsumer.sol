pragma solidity ^0.5.1;


interface OracleConsumer {
    function receiveResult(bytes32 id, bytes calldata result) external;
}
