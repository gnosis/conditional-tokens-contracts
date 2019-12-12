# Audit report
## Gnosis Conditional Tokens

## Files

All solidity files in the following repository:

https://github.com/gnosis/conditional-tokens-contracts/tree/a050b6c16aba8e3bfd6697e9a68bd23aeba307b4

## Issues

## 1. By splitting non-existent collections it's possible to forge other collections and ultimately steal all collateral tokens from the contract

### type: security / severity: critical

It's possible to split non-existent position tokens so that some of the resulting tokens will share the same `collectionId` as a different position, this is possible for three reasons:

### a)

When splitting tokens, these tokens are destroyed only after the tokens resulting from the split have been created

### b)
When new tokens are created and transferred to the recipient, `onERC1155Received` function on the recipient's address is called allowing re-entracny of the `ConditionalTokens` contract

### c)

Complex `collectionId`s are derived in a predictable way from the `collectionId`s of included positions. `collectionId` of a complex position is a simple sum of all contained positions. This allows attacker to craft a position that upon splitting will result in tokens that have a `collectionId` that collides with a different position. 
For example collection with `collectionId`: `bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10))))` when split will result in collections with ids: 

`bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01)))` (if `0b01` is the winning outcome, this position can be directly redeemed as collateral)
and 
`bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) + uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10))))` which if `0b01` is the winning outcome can be be redeemed back into `bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10))))` in full making sure the original split terminates correctly.

### Replication

We assume that `0b01` is the winning position of condition with id `conditionId`

```
splitPosition(
    collateralToken, 
    bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10)))), 
    conditionId,
    [0b10, 0b01],
    amount
)

    ConditionalTokens._mint(..) -> msg.sender.onERC1155Received(..) -> 

            redeemPositions(
                collateralToken,
                bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10)))),
                conditionId,
                [0b01]
            ) //redeems `amount` of position of collection with id `bytes32(uint(keccak256(abi.encodePacked(conditionId, 0b01))) - uint(keccak256(abi.encodePacked(conditionId, 0b10))))` so that splitPosition can burn it and successfully terminate

            redeemPositions(
                collateralToken,
                bytes32(0),
                conditionId,
                [0b01]
            ) //redeems collateral from the winning position that has been forged
```


### fixed

The issue was addressed by burning tokens before minting new ones and is no longer present in: https://github.com/gnosis/conditional-tokens-contracts/tree/4afa2fed1dfa62d8f413e126f238811f1d40bbfc


## 2. Used multihash algorithm vulnerable to generalised birthday attack

### type: security / severity: critical

Ids of complex collections are sums of hashes of data describing simple collections (algorithm that was introduced as AdHash in: http://cseweb.ucsd.edu/~mihir/papers/inchash.pdf). Unfortunately there are known practical techniques that allow finding sets of different hashes that sum to the same number, opening the indexing system to fatal collision attacks (for details of such attack see: http://www.cs.berkeley.edu/~daw/papers/genbday-long.ps).

### addressed

The issue was addressed by replacing the AdHash algorithm with Elliptic Curve Multiset Hash (see: https://arxiv.org/abs/1601.06502), this seems like a promising solution but the implementation (present in https://github.com/gnosis/conditional-tokens-contracts/tree/4afa2fed1dfa62d8f413e126f238811f1d40bbfc) is still pending evaluation. 


## 3. Possible efficiency gains by adding a batch mint nethod to ERC1155 contract

### type: efficiency / severity: minor

Adding a batch mint in ERC1155 that invokes `_doSafeBatchTransferAcceptanceCheck` instead of `_doSafeTransferAcceptanceCheck` might be useful because `ConditionalTokens.sol:L126` can be executed a lot of times and generate a lot of external calls through `_doSafeTransferAcceptanceCheck`.

### fixed

Batch mint has been added https://github.com/gnosis/conditional-tokens-contracts/tree/4afa2fed1dfa62d8f413e126f238811f1d40bbfc