// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.1;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import { ERC1155WithMappedAddresses } from "restorable-funds/contracts/ERC1155WithMappedAddresses.sol";
import { IERC1155TokenReceiver } from "./ERC1155/IERC1155TokenReceiver.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// TODO: Staking makes it important to easily set the swap date.
// TODO: Allocate to oracles a portion of the conditional token and/or collateral, rather than the collateral.
// TODO: Allow to lock staked tokens? (as a separate contract?)
// TODO: Move to another Ethereum account without a confirmation, using the old account.

// TODO: Token URL setting.
/// @title Bidding on Ethereum addresses
/// @author Victor Porton
/// @notice Not audited, not enough tested.
/// This allows anyone claim 1000 conditional tokens in order for him to transfer money from the future.
/// See `docs/future-money.rst`.
///
/// We have three kinds of ERC-1155 token ID
/// - a combination of market ID, collateral address, and customer address (conditional tokens)
/// - a combination of TOKEN_STAKED and collateral address (staked collateral tokens)
/// - a combination of TOKEN_SUMMARY and collateral address (staked + staked collateral tokens)
///
/// In functions of this contact `condition` is always a customer's original address.
abstract contract BaseBidOnAddresses is ERC1155WithMappedAddresses, IERC1155TokenReceiver {
    // TODO: IERC1155Views
    // TODO: Allocate also kX tokens to the DAO.
    // TODO: Does it make sense to be able to change the amount of salary per second?

    using ABDKMath64x64 for int128;
    using SafeMath for uint256;

    enum TokenKind { TOKEN_CONDITIONAL, TOKEN_DONATED, TOKEN_STAKED }

    event MarketCreated(address creator, uint64 marketId);

    event OracleCreated(address oracleOwner, uint64 oracleId);

    event OracleOwnerChanged(address oracleOwner, uint64 oracleId);

    event DonateCollateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        address to,
        bytes data
    );

    event StakeCollateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        address to,
        bytes data
    );

    event TakeBackCollateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        address to
    );

    event ConvertStakedToDonated(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        address to,
        bytes data
    );

    event ReportedNumerator(
        uint64 indexed oracleId,
        address customer,
        uint256 numerator
    );

    event ReportedNumeratorsBatch(
        uint64 indexed oracleId,
        address[] addresses,
        uint256[] numerators
    );

    event OracleFinished(address indexed oracleOwner);

    event RedeemCalculated(
        address user,
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        uint64 indexed marketId,
        uint64 indexed oracleId,
        address condition,
        uint payout
    );

    event CollateralWithdrawn(
        IERC1155 contractAdrress,
        uint256 collateralTokenId,
        uint64 marketId,
        uint64 oracleId,
        address user,
        uint256 amount
    );
    
    uint64 private maxId;

    // Mapping from oracleId to oracle owner.
    mapping(uint64 => address) private oracleOwnersMap;
    // Whether an oracle finished its work.
    mapping(uint64 => bool) private oracleFinishedMap;
    // Mapping (marketId => (customer => numerator)) for payout numerators.
    mapping(uint64 => mapping(address => uint256)) private payoutNumeratorsMap;
    // Mapping (marketId => denominator) for payout denominators.
    mapping(uint64 => uint) private payoutDenominatorMap;
    // Total collaterals (separately donated and staked) per marketId and oracleId: collateral => (marketId => (oracleId => total)).
    mapping(uint256 => uint256) private collateralTotalsMap;
    // If a given conditional was already redeemed.
    mapping(address => mapping(uint64 => mapping(uint256 => bool))) private redeemActivatedMap; // TODO: hash instead?
    // The user lost the right to transfer conditional tokens: (user => (conditionalToken => bool)).
    mapping(address => mapping(uint256 => bool)) private userUsedRedeemMap;

    constructor(string memory uri_) ERC1155WithMappedAddresses(uri_) {
        _registerInterface(
            BaseBidOnAddresses(0).onERC1155Received.selector ^
            BaseBidOnAddresses(0).onERC1155BatchReceived.selector
        );
    }

    /// Create a new conditional marketId
    function createMarket() external returns (uint64) {
        uint64 marketId = maxId++;
        emit MarketCreated(msg.sender, marketId);
        return marketId;
    }

    /// Create a new oracle
    function createOracle() external returns (uint64) {
        uint64 oracleId = maxId++;
        oracleOwnersMap[oracleId] = msg.sender;
        emit OracleCreated(msg.sender, oracleId);
        emit OracleOwnerChanged(msg.sender, oracleId);
        return oracleId;
    }

    function changeOracleOwner(address newOracleOwner, uint64 oracleId) public _isOracle(oracleId) {
        oracleOwnersMap[oracleId] = newOracleOwner;
        emit OracleOwnerChanged(newOracleOwner, oracleId);
    }

    /// Donate funds in a ERC1155 token.
    /// First need to approve the contract to spend the token.
    /// Not recommended to donate after any oracle has finished, because funds may be (partially) lost.
    function donate(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        uint64 marketId,
        uint64 oracleId,
        uint256 amount,
        address to,
        bytes calldata data) external
    {
        _mint(to, _collateralDonatedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId), amount, data);
        uint donatedCollateralTokenId = _collateralDonatedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        collateralTotalsMap[donatedCollateralTokenId] = collateralTotalsMap[donatedCollateralTokenId].add(amount);
        emit DonateCollateral(collateralContractAddress, collateralTokenId, msg.sender, amount, to, data);
        collateralContractAddress.safeTransferFrom(msg.sender, address(this), collateralTokenId, amount, data); // last against reentrancy attack
    }

    /// Stake funds in a ERC1155 token.
    /// First need to approve the contract to spend the token.
    /// The stake is lost if either: the prediction period ends or the staker loses his private key (e.g. dies).
    /// Not recommended to stake after the oracle has finished, because funds may be (partially) lost (you could not unstake).
    function stakeCollateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        uint64 marketId,
        uint64 oracleId,
        uint256 amount,
        address to,
        bytes calldata data) external
    {
        _mint(to, _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId), amount, data);
        uint stakedCollateralTokenId = _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        collateralTotalsMap[stakedCollateralTokenId] = collateralTotalsMap[stakedCollateralTokenId].add(amount);
        emit StakeCollateral(collateralContractAddress, collateralTokenId, msg.sender, amount, to, data);
        collateralContractAddress.safeTransferFrom(msg.sender, address(this), collateralTokenId, amount, data); // last against reentrancy attack
    }

    /// If the oracle has not yet finished you can take funds back.
    function takeStakeBack(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        uint64 marketId,
        uint64 oracleId,
        uint256 amount,
        address to,
        bytes calldata data) external
    {
        require(oracleFinishedMap[oracleId], "too late");
        uint stakedCollateralTokenId = _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        collateralTotalsMap[stakedCollateralTokenId] = collateralTotalsMap[stakedCollateralTokenId].sub(amount);
        collateralContractAddress.safeTransferFrom(address(this), to, stakedCollateralTokenId, amount, data);
        emit TakeBackCollateral(collateralContractAddress, collateralTokenId, msg.sender, amount, to);
    }

    /// Donate funds from your stake.
    function convertStakedToDonated(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        uint64 marketId,
        uint64 oracleId,
        uint256 amount,
        address to,
        bytes calldata data) external
    {
        // Subtract from staked:
        uint stakedCollateralTokenId = _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        _burn(msg.sender, stakedCollateralTokenId, amount);
        collateralTotalsMap[stakedCollateralTokenId] = collateralTotalsMap[stakedCollateralTokenId].sub(amount);
        // Add to donated:
        uint donatedCollateralTokenId = _collateralDonatedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        _mint(to, donatedCollateralTokenId, amount, data);
        collateralTotalsMap[donatedCollateralTokenId] = collateralTotalsMap[donatedCollateralTokenId].add(amount);
        emit ConvertStakedToDonated(collateralContractAddress, collateralTokenId, msg.sender, amount, to, data);
    }

    /// @dev Called by the oracle owner for reporting results of conditions.
    function reportNumerator(uint64 oracleId, address condition, uint256 numerator) external
        _isOracle(oracleId)
    {
        _updateNumerator(oracleId, numerator, condition);
        emit ReportedNumerator(oracleId, condition, numerator);
    }

    /// @dev Called by the oracle owner for reporting results of conditions.
    function reportNumeratorsBatch(uint64 oracleId, address[] calldata addresses, uint256[] calldata numerators) external
        _isOracle(oracleId)
    {
        require(addresses.length == numerators.length, "Length mismatch.");
        for (uint i = 0; i < addresses.length; ++i) {
            _updateNumerator(oracleId, numerators[i], addresses[i]);
        }
        emit ReportedNumeratorsBatch(oracleId, addresses, numerators);
    }

    /// Need to be called after all numerators were reported.
    function finishOracle(uint64 oracleId) external
        _isOracle(oracleId)
    {
        oracleFinishedMap[oracleId] = true;
        emit OracleFinished(msg.sender);
    }

    /// Transfer to `msg.sender` the collateral ERC-20 token (we can't transfer to somebody other, because anybody can transfer).
    /// accordingly to the score of `condition` in the marketId by the oracle.
    /// After this function is called, it becomes impossible to transfer the corresponding conditional token of `msg.sender`
    /// (to prevent its repeated withdraw).
    function withdrawCollateral(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, address condition, bytes calldata data) external {
        require(oracleFinishedMap[oracleId], "too early"); // to prevent the denominator or the numerators change meantime
        uint256 collateralBalance = _initialCollateralBalanceOf(collateralContractAddress, collateralTokenId, marketId, oracleId, msg.sender, condition);
        uint256 conditionalTokenId = _conditionalTokenId(marketId, condition);
        address _originalAddress = originalAddress(msg.sender);
        require(!redeemActivatedMap[_originalAddress][oracleId][conditionalTokenId], "Already redeemed.");
        redeemActivatedMap[_originalAddress][oracleId][conditionalTokenId] = true;
        userUsedRedeemMap[_originalAddress][conditionalTokenId] = true;
        // _burn(msg.sender, conditionalTokenId, conditionalBalance); // Burning it would break using the same token for multiple outcomes.
        collateralContractAddress.safeTransferFrom(address(this), msg.sender, collateralTokenId, collateralBalance, data); // last to prevent reentrancy attack
    }

    /// Calculate the collateral balance corresponding to the current conditonal token `condition` state and
    /// current numerators.
    /// This function can be called before oracle is finished, but that's not recommended.
    function initialCollateralBalanceOf(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, address user, address condition) external view returns (uint256) {
        return _initialCollateralBalanceOf(collateralContractAddress, collateralTokenId, marketId, oracleId, user, condition);
    }

    /// Disallow transfers of conditional tokens after redeem to prevent "gathering" them before redeeming each oracle.
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        public override
    {
        _checkTransferAllowed(id, from);
        _baseSafeTransferFrom(from, to, id, value, data);
    }

    /// Disallow transfers of conditional tokens after redeem to prevent "gathering" them before redeeming each oracle.
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        public override
    {
        for(uint i = 0; i < ids.length; ++i) {
            _checkTransferAllowed(ids[i], from);
        }
        _baseSafeBatchTransferFrom(from, to, ids, values, data);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) public pure override returns(bytes4) {
        return this.onERC1155Received.selector; // to accept transfers
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) public pure override returns(bytes4) {
        return bytes4(0); // We should never receive batch transfers.
    }

    // Getters //

    function summaryCollateral(address user, uint256 donatedCollateralTokenId, uint256 stakedCollateralTokenId) public view returns (uint256) {
        return balanceOf(user, donatedCollateralTokenId) + balanceOf(user, stakedCollateralTokenId);
    }

    function summaryCollateralTotal(uint256 donatedCollateralTokenId, uint256 stakedCollateralTokenId) public view returns (uint256) {
        return collateralTotalsMap[donatedCollateralTokenId] + collateralTotalsMap[stakedCollateralTokenId];
    }

    function oracleOwner(uint64 oracleId) public view returns (address) {
        return oracleOwnersMap[oracleId];
    }

    function isOracleFinished(uint64 oracleId) public view returns (bool) {
        return oracleFinishedMap[oracleId];
    }

    function payoutNumerator(uint64 marketId, address condition) public view returns (uint256) {
        return payoutNumeratorsMap[marketId][condition];
    }

    function payoutDenominator(uint64 marketId) public view returns (uint256) {
        return payoutDenominatorMap[marketId];
    }

    /// @param hash should be a result of `_collateralStakedTokenId()`.
    function collateralTotal(uint256 hash) public view returns (uint256) {
        return collateralTotalsMap[hash];
    }

    function isRedeemActivated(address condition, uint64 oracleId, uint256 conditionalTokenId) public view returns (bool) {
        return redeemActivatedMap[condition][oracleId][conditionalTokenId];
    }

    function isConditonalLocked(address condition, uint256 conditionalTokenId) public view returns (bool) {
        return userUsedRedeemMap[condition][conditionalTokenId];
    }

    function marketTotal(address /*condition*/) public virtual view returns (uint256);

    // Internal //

    function _initialCollateralBalanceOf(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, address user, address condition) internal view
        returns (uint256)
    {
        uint256 numerator = payoutNumeratorsMap[oracleId][condition];
        uint256 denominator = payoutDenominatorMap[oracleId];
        uint256 conditonalBalance = balanceOf(user, _conditionalTokenId(marketId, condition));
        uint donatedCollateralTokenId = _collateralDonatedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        uint stakedCollateralTokenId = _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        uint256 collateralTotalBalance = summaryCollateralTotal(donatedCollateralTokenId, stakedCollateralTokenId);
        // Rounded to below for no out-of-funds:
        int128 marketIdShare = ABDKMath64x64.divu(conditonalBalance, marketTotal(condition));
        int128 rewardShare = ABDKMath64x64.divu(numerator, denominator);
        return marketIdShare.mul(rewardShare).mulu(collateralTotalBalance);
    }

    function _conditionalTokenId(uint64 marketId, address condition) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_CONDITIONAL), marketId, condition)));
    }

    function _collateralDonatedTokenId(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_DONATED), collateralContractAddress, collateralTokenId, marketId, oracleId)));
    }

    function _collateralStakedTokenId(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_STAKED), collateralContractAddress, collateralTokenId, marketId, oracleId)));
    }

    function _checkTransferAllowed(uint256 id, address from) internal view {
        require(!userUsedRedeemMap[originalAddress(from)][id], "You can't trade conditional tokens after redeem.");
    }

    function _baseSafeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    )
        private
    {
        require(to != address(0), "ERC1155: target address must be non-zero");
        require(
            from == msg.sender || _operatorApprovals[from][msg.sender] == true,
            "ERC1155: need operator approval for 3rd party transfers."
        );

        // TODO: duplicateCode
        address originalFrom = originalAddress(from);
        _balances[id][originalFrom] = _balances[id][originalFrom].sub(value);
        address originalTo = originalAddress(to);
        _balances[id][originalTo] = value.add(_balances[id][originalTo]);

        emit TransferSingle(msg.sender, from, to, id, value);

        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, value, data);
    }

    function _baseSafeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        private
    {
        require(ids.length == values.length, "ERC1155: IDs and values must have same lengths");
        require(to != address(0), "ERC1155: target address must be non-zero");
        require(
            from == msg.sender || _operatorApprovals[from][msg.sender] == true,
            "ERC1155: need operator approval for 3rd party transfers."
        );

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 value = values[i];

            // TODO: duplicateCode
            address originalFrom = originalAddress(from);
            _balances[id][originalFrom] = _balances[id][originalFrom].sub(value);
            address originalTo = originalAddress(to);
            _balances[id][originalTo] = value.add(_balances[id][originalTo]);
        }

        emit TransferBatch(msg.sender, from, to, ids, values);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, values, data);
    }

    function _updateNumerator(uint64 oracleId, uint256 numerator, address condition) private {
        payoutDenominatorMap[oracleId] = payoutDenominatorMap[oracleId].add(numerator).sub(payoutNumeratorsMap[oracleId][condition]);
        payoutNumeratorsMap[oracleId][condition] = numerator;
    }

    modifier _isOracle(uint64 oracleId) {
        require(oracleOwnersMap[oracleId] == msg.sender, "Not the oracle owner.");
        _;
    }
}
