pragma solidity ^0.5.1;
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { IERC1155TokenReceiver } from "./ERC1155/IERC1155TokenReceiver.sol";
import { ERC1155TokenReceiver } from "./ERC1155/ERC1155TokenReceiver.sol";
import { IERC1155 } from "./ERC1155/IERC1155.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";


contract ConditionalTokens is ERC1155, ERC1155TokenReceiver {

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
    event PositionSplit(
        address indexed stakeholder,
        IERC1155 collateralToken,
        uint collateralTokenID,
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
    event PositionsMerge(
        address indexed stakeholder,
        IERC1155 collateralToken,
        uint collateralTokenID,
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

    enum CollateralTypes { ERC20, ERC1155 }

    /// Mapping key is an condition ID. Value represents numerators of the payout vector associated with the condition. This array is initialized with a length equal to the outcome slot count.
    mapping(bytes32 => uint[]) public payoutNumerators;
    mapping(bytes32 => uint) public payoutDenominator;

    /// @dev This function prepares a condition by initializing a payout vector associated with the condition.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external {
        require(outcomeSlotCount <= 256, "too many outcome slots");
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        bytes32 conditionId = getConditionId(oracle, questionId, outcomeSlotCount);
        require(payoutNumerators[conditionId].length == 0, "condition already prepared");
        payoutNumerators[conditionId] = new uint[](outcomeSlotCount);
        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    /// @param questionId The question ID the oracle is answering for
    /// @param payouts The oracle's answer
    function reportPayouts(bytes32 questionId, uint[] calldata payouts) external {
        uint outcomeSlotCount = payouts.length;
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        bytes32 conditionId = getConditionId(msg.sender, questionId, outcomeSlotCount);
        require(payoutNumerators[conditionId].length == outcomeSlotCount, "condition not prepared or found");
        require(payoutDenominator[conditionId] == 0, "payout denominator already set");
        uint den = 0;
        for (uint i = 0; i < outcomeSlotCount; i++) {
            uint num = payouts[i];
            den = den.add(num);

            require(payoutNumerators[conditionId][i] == 0, "payout numerator already set");
            payoutNumerators[conditionId][i] = num;
        }
        payoutDenominator[conditionId] = den;
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
        (uint fullIndexSet, uint freeIndexSet) = mintSet(msg.sender, CollateralTypes.ERC20, address(collateralToken), 0, parentCollectionId, conditionId, partition, amount);

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transferFrom(msg.sender, address(this), amount), "could not receive collateral tokens");
            } else {
                _burn(
                    msg.sender,
                    getPositionId(collateralToken, parentCollectionId),
                    amount
                );
            }
        } else {
            _burn(
                msg.sender,
                getPositionId(collateralToken,
                    getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount
            );
        }

        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function split1155Position(
        IERC1155 collateralToken,
        uint collateralTokenID,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        (uint fullIndexSet, uint freeIndexSet) = mintSet(msg.sender, CollateralTypes.ERC1155, address(collateralToken), collateralTokenID, parentCollectionId, conditionId, partition, amount);

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                collateralToken.safeTransferFrom(msg.sender, address(this), collateralTokenID, amount, "");
            } else {
                _burn(
                    msg.sender,
                    getPositionId(collateralToken, collateralTokenID, parentCollectionId),
                    amount
                );
            }
        } else {
            _burn(
                msg.sender,
                getPositionId(collateralToken, collateralTokenID,
                    getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount
            );
        }

        emit PositionSplit(msg.sender, collateralToken, collateralTokenID, parentCollectionId, conditionId, partition, amount);
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

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint freeIndexSet = fullIndexSet;
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            freeIndexSet ^= indexSet;
            _burn(
                msg.sender,
                getPositionId(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet)),
                amount
            );
        }

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transfer(msg.sender, amount), "could not send collateral tokens");
            } else {
                _mint(
                    msg.sender,
                    getPositionId(collateralToken, parentCollectionId),
                    amount,
                    ""
                );
            }
        } else {
            _mint(
                msg.sender,
                getPositionId(collateralToken,
                    getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount,
                ""
            );
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function merge1155Positions(
        IERC1155 collateralToken,
        uint collateralTokenID,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint freeIndexSet = fullIndexSet;
        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            freeIndexSet ^= indexSet;
            _burn(
                msg.sender,
                getPositionId(collateralToken, collateralTokenID,
                    getCollectionId(parentCollectionId, conditionId, indexSet)),
                amount
            );
        }

        if (freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                collateralToken.safeTransferFrom(address(this), msg.sender, collateralTokenID, amount, "");
            } else {
                _mint(
                    msg.sender,
                    getPositionId(collateralToken, collateralTokenID, parentCollectionId),
                    amount,
                    ""
                );
            }
        } else {
            _mint(
                msg.sender,
                getPositionId(collateralToken, collateralTokenID,
                    getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)),
                amount,
                ""
            );
        }

        emit PositionsMerge(msg.sender, collateralToken, collateralTokenID, parentCollectionId, conditionId, partition, amount);
    }

    function mintSet(
        address recipient,
        CollateralTypes collateralType,
        address collateralToken,
        uint collateralTokenID,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] memory partition,
        uint amount
    ) private returns (uint fullIndexSet, uint freeIndexSet) {
        {
            uint outcomeSlotCount = payoutNumerators[conditionId].length;
            require(outcomeSlotCount > 0, "condition not prepared yet");
            fullIndexSet = (1 << outcomeSlotCount) - 1;
            freeIndexSet = fullIndexSet;
        }

        for (uint i = 0; i < partition.length; i++) {
            uint indexSet = partition[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            require((indexSet & freeIndexSet) == indexSet, "partition not disjoint");
            freeIndexSet ^= indexSet;
            _mint(
                recipient,
                collateralType == CollateralTypes.ERC20 ?
                    getPositionId(IERC20(collateralToken), getCollectionId(parentCollectionId, conditionId, indexSet)) :
                    getPositionId(IERC1155(collateralToken), collateralTokenID, getCollectionId(parentCollectionId, conditionId, indexSet)),
                amount,
                ""
            );
        }
    }

    function redeemPositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint[] calldata indexSets) external {
        uint den = payoutDenominator[conditionId];
        require(den > 0, "result for condition not received yet");
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        uint totalPayout = 0;

        uint fullIndexSet = (1 << outcomeSlotCount) - 1;
        for (uint i = 0; i < indexSets.length; i++) {
            uint indexSet = indexSets[i];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            uint positionId = getPositionId(collateralToken,
                getCollectionId(parentCollectionId, conditionId, indexSet));

            uint payoutNumerator = 0;
            for (uint j = 0; j < outcomeSlotCount; j++) {
                if (indexSet & (1 << j) != 0) {
                    payoutNumerator = payoutNumerator.add(payoutNumerators[conditionId][j]);
                }
            }

            uint payoutStake = balanceOf(msg.sender, positionId);
            if (payoutStake > 0) {
                totalPayout = totalPayout.add(payoutStake.mul(payoutNumerator).div(den));
                _burn(msg.sender, positionId, payoutStake);
            }
        }

        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                require(collateralToken.transfer(msg.sender, totalPayout), "could not transfer payout to message sender");
            } else {
                _mint(msg.sender, getPositionId(collateralToken, parentCollectionId), totalPayout, "");
            }
        }
        emit PayoutRedemption(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    function onERC1155Received(
        address operator,
        address /* from */,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        if(operator != address(this)) {
            (bytes32 conditionId, uint[] memory partition) = abi.decode(data, (bytes32, uint[]));
            (uint fullIndexSet, uint freeIndexSet) = mintSet(operator, CollateralTypes.ERC1155, msg.sender, id, bytes32(0), conditionId, partition, value);
            require(freeIndexSet == 0, "must partition entire outcome slot set");
        }

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address /* from */,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        revert("operation not supported");
    }

    /// @dev Gets the outcome slot count of a condition.
    /// @param conditionId ID of the condition.
    /// @return Number of outcome slots associated with a condition, or zero if condition has not been prepared yet.
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint) {
        return payoutNumerators[conditionId].length;
    }

    /// @dev Constructs a condition ID from an oracle, a question ID, and the outcome slot count for the question.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function getConditionId(address oracle, bytes32 questionId, uint outcomeSlotCount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /// @dev Constructs an outcome collection ID from a parent collection and an outcome collection.
    /// @param parentCollectionId Collection ID of the parent outcome collection, or bytes32(0) if there's no parent.
    /// @param conditionId Condition ID of the outcome collection to combine with the parent outcome collection.
    /// @param indexSet Index set of the outcome collection to combine with the parent outcome collection.
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint indexSet) public pure returns (bytes32) {
        return bytes32(
            uint(parentCollectionId) +
            uint(keccak256(abi.encodePacked(conditionId, indexSet)))
        );
    }

    /// @dev Constructs a position ID from a collateral token and an outcome collection. These IDs are used as the ERC-1155 ID for this contract.
    /// @param collateralToken Collateral token which backs the position.
    /// @param collectionId ID of the outcome collection associated with this position.
    function getPositionId(IERC20 collateralToken, bytes32 collectionId) public pure returns (uint) {
        return uint(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function getPositionId(IERC1155 collateralToken, uint collateralTokenID, bytes32 collectionId) public pure returns (uint) {
        return uint(keccak256(abi.encodePacked(collateralToken, collateralTokenID, collectionId)));
    }
}
