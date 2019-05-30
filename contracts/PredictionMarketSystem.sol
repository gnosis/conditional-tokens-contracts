pragma solidity ^0.5.1;
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { IERC1155TokenReceiver } from "./ERC1155/IERC1155TokenReceiver.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";
import "./OracleConsumer.sol";


contract PredictionMarketSystem is OracleConsumer, ERC1155 {

    /// @dev Emitted upon the successful preparation of a condition.
    /// @param conditionId The condition's ID. This ID may be derived from the other three parameters via ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount
    );

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount,
        uint[] payoutNumerators
    );

    /// @dev Emitted when a position is successfully split.
    event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    );
    /// @dev Emitted when positions are successfully merged.
    event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    );
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint[] indexSets,
        uint payout
    );

    /// Mapping key is an condition ID. Value represents numerators of the payout vector associated with the condition. This array is initialized with a length equal to the outcome slot count.
    mapping(bytes32 => uint[]) public payoutNumerators;
    mapping(bytes32 => uint) public payoutDenominator;

    /// @dev This function prepares a condition by initializing a payout vector associated with the condition.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external {
        require(outcomeSlotCount <= 256, "too many outcome slots");
        bytes32 conditionId = keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
        require(payoutNumerators[conditionId].length == 0, "condition already prepared");
        payoutNumerators[conditionId] = new uint[](outcomeSlotCount);
        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is derived from result, which is the result of serializing 32-byte EVM words representing payoutNumerators for each outcome slot of the condition.
    /// @param questionId The question ID the oracle is answering for
    /// @param result The oracle's answer
    function receiveResult(bytes32 questionId, bytes calldata result) external {
        require(result.length > 0, "results empty");
        require(result.length % 32 == 0, "results not 32-byte aligned");
        uint outcomeSlotCount = result.length / 32;
        require(outcomeSlotCount <= 256, "too many outcome slots");
        bytes32 conditionId = keccak256(abi.encodePacked(msg.sender, questionId, outcomeSlotCount));
        require(payoutNumerators[conditionId].length == outcomeSlotCount, "number of outcomes mismatch");
        require(payoutDenominator[conditionId] == 0, "payout denominator already set");
        for (uint i = 0; i < outcomeSlotCount; i++) {
            uint payoutNum;
            // solium-disable-next-line security/no-inline-assembly
            assembly {
                payoutNum := calldataload(add(0x64, mul(0x20, i)))
            }
            payoutDenominator[conditionId] = payoutDenominator[conditionId].add(payoutNum);

            require(payoutNumerators[conditionId][i] == 0, "payout numerator already set");
            payoutNumerators[conditionId][i] = payoutNum;
        }
        require(payoutDenominator[conditionId] > 0, "payout is all zeroes");
        emit ConditionResolution(conditionId, msg.sender, questionId, outcomeSlotCount, payoutNumerators[conditionId]);
    }

    /// @dev This function splits a position. If splitting from the collateral, this contract will attempt to transfer `amount` collateral from the message sender to itself. Otherwise, this contract will burn `amount` stake held by the message sender in the position being split. Regardless, if successful, `amount` stake will be minted in the split target positions. If any of the transfers, mints, or burns fail, the transaction will revert. The transaction will also revert if the given partition is trivial, invalid, or refers to more slots than the condition is prepared with.
    /// @param collateralToken The address of the positions' backing collateral token.
    /// @param parentCollectionId The ID of the outcome collections common to the position being split and the split target positions. May be null, in which only the collateral is shared.
    /// @param conditionId The ID of the condition to split on.
    /// @param partition An array of disjoint index sets representing a nontrivial partition of the outcome slots of the given condition.
    /// @param amount The amount of collateral or stake to split.
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        bytes32 key;

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint freeIndexSet = fullIndexSet;
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            freeIndexSet ^= indexSet;
            key = keccak256(abi.encodePacked(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet)));
            _mint(msg.sender, uint(key), amount, "");
        }

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transferFrom(msg.sender, address(this), amount), "could not receive collateral tokens");
            } else {
                key = keccak256(abi.encodePacked(collateralToken, parentCollectionId));
                _burn(msg.sender, uint(key), amount);
            }
        } else {
            key = keccak256(abi.encodePacked(collateralToken, getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)));
            _burn(msg.sender, uint(key), amount);
        }

        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        bytes32 key;

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint freeIndexSet = fullIndexSet;
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            freeIndexSet ^= indexSet;
            key = keccak256(abi.encodePacked(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet)));
            _burn(msg.sender, uint(key), amount);
        }

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transfer(msg.sender, amount), "could not send collateral tokens");
            } else {
                key = keccak256(abi.encodePacked(collateralToken, parentCollectionId));
                _mint(msg.sender, uint(key), amount, "");
            }
        } else {
            key = keccak256(abi.encodePacked(collateralToken, getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)));
            _mint(msg.sender, uint(key), amount, "");
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function redeemPositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint[] calldata indexSets) external {
        require(payoutDenominator[conditionId] > 0, "result for condition not received yet");
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        uint totalPayout = 0;
        bytes32 key;

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        for (uint i = 0; i < indexSets.length; i++) {
            uint indexSet = indexSets[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            key = keccak256(abi.encodePacked(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet)));

            uint payoutNumerator = 0;
            for (uint j = 0; j < outcomeSlotCount; j++) {
                if (indexSet & (1 << j) != 0) {
                    payoutNumerator = payoutNumerator.add(payoutNumerators[conditionId][j]);
                }
            }

            uint payoutStake = balanceOf(msg.sender, uint(key));
            if (payoutStake > 0) {
                totalPayout = totalPayout.add(payoutStake.mul(payoutNumerator).div(payoutDenominator[conditionId]));
                _burn(msg.sender, uint(key), payoutStake);
            }
        }

        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transfer(msg.sender, totalPayout), "could not transfer payout to message sender");
            } else {
                key = keccak256(abi.encodePacked(collateralToken, parentCollectionId));
                _mint(msg.sender, uint(key), totalPayout, "");
            }
        }
        emit PayoutRedemption(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    /// @dev Gets the outcome slot count of a condition.
    /// @param conditionId ID of the condition.
    /// @return Number of outcome slots associated with a condition, or zero if condition has not been prepared yet.
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint) {
        return payoutNumerators[conditionId].length;
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint indexSet) private pure returns (bytes32) {
        return bytes32(
            uint(parentCollectionId) +
            uint(keccak256(abi.encodePacked(conditionId, indexSet)))
        );
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    )
        internal
    {
        if(to.isContract()) {
            (bool callSucceeded, bytes memory callReturnData) = to.call(abi.encodeWithSignature(
                "onERC1155Received(address,address,uint256,uint256,bytes)",
                operator, from, id, value, data
            ));

            if(callSucceeded) {
                require(
                    abi.decode(callReturnData, (bytes4)) ==
                        IERC1155TokenReceiver(to).onERC1155Received.selector,
                    "ERC1155: got unknown value from onERC1155Received"
                );
            } else {
                // is this a terrible idea? yes. yes it is.
                require(callReturnData.length == 0, string(callReturnData));
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        internal
    {
        if(to.isContract()) {
            (bool callSucceeded, bytes memory callReturnData) = to.call(abi.encodeWithSignature(
                "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)",
                operator, from, ids, values, data
            ));

            if(callSucceeded) {
                require(
                    abi.decode(callReturnData, (bytes4)) ==
                        IERC1155TokenReceiver(to).onERC1155Received.selector,
                    "ERC1155: got unknown value from onERC1155Received"
                );
            } else {
                require(callReturnData.length == 0, string(callReturnData));
            }
        }
    }
}
