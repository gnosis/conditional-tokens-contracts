pragma solidity ^0.5.1;
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import { IERC1155 } from "./ERC1155/IERC1155.sol";
import { IERC1155TokenReceiver } from "./ERC1155/IERC1155TokenReceiver.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";

/// @title Bidding on Ethereum addresses
/// @author Victor Porton
/// @notice Not audited, not enough tested.
/// This allows anyone claim 1000 conditional tokens in order for him to transfer money from the future.
/// See `docs/future-money.rst`.
///
/// We have four kinds of ERC-1155 token ID
/// - a combination of market ID, collateral address, and customer address (conditional tokens)
/// - a combination of TOKEN_STAKED and collateral address (staked collateral tokens)
/// - a combination of TOKEN_SUMMARY and collateral address (staked + staked collateral tokens)
contract BidOnAddresses is ERC1155, IERC1155TokenReceiver {
    using ABDKMath64x64 for int128;

    enum TokenKind { TOKEN_CONDITIONAL, TOKEN_STAKED, TOKEN_SUMMARY }

    uint constant INITIAL_CUSTOMER_BALANCE = 1000 * 10**18; // an arbitrarily choosen value

    event MarketCreated(address creator, uint64 marketId);

    event OracleCreated(address oracleOwner, uint64 oracleId);

    event CustomerRegistered(
        address customer,
        uint64 marketId,
        bytes data
    );

    event DonateERC20Collateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        bytes data
    );

    event StakeERC20Collateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount,
        bytes data
    );

    event TakeBackERC20Collateral(
        IERC1155 collateralContractAddress,
        uint256 collateralTokenId,
        address sender,
        uint256 amount
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

    /// Mapping from oracleId to oracle owner.
    mapping(uint64 => address) private oracleOwnersMap;
    /// Whether an oracle finished its work.
    mapping(uint64 => bool) private oracleFinishedMap;
    /// Mapping (marketId => (customer => numerator)) for payout numerators.
    mapping(uint64 => mapping(address => uint256)) private payoutNumeratorsMap;
    /// Mapping (marketId => denominator) for payout denominators.
    mapping(uint64 => uint) private payoutDenominatorMap;
    /// All conditional tokens,
    mapping(uint256 => bool) private conditionalTokensMap;
    /// Total collaterals per marketId and oracleId: collateral => (marketId => (oracleId => total))
    mapping(uint256 => uint256) private collateralTotalsMap;
    /// If a given conditional was already redeemed.
    mapping(address => mapping(uint64 => mapping(uint256 => bool))) private redeemActivatedMap; // TODO: hash instead?
    /// The user lost the right to transfer conditional tokens: (user => (conditionalToken => bool)).
    mapping(address => mapping(uint256 => bool)) private userUsedRedeemMap;

    constructor() public {
        _registerInterface(
            BidOnAddresses(0).onERC1155Received.selector ^
            BidOnAddresses(0).onERC1155BatchReceived.selector
        );
    }

    /// Create a new conditional marketId
    function createMarket() external {
        uint64 marketId = maxId++;
        emit MarketCreated(msg.sender, marketId);
    }

    /// Create a new oracle
    function createOracle() external {
        uint64 oracleId = maxId++;
        oracleOwnersMap[oracleId] = msg.sender;
        emit OracleCreated(msg.sender, oracleId);
    }

    /// Donate funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// Not recommended to donate after any oracle has finished, because funds may be (partially) lost.
    function donate(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralContractAddress, collateralTokenId, marketId, oracleId, amount, data);
        emit DonateERC20Collateral(collateralContractAddress, collateralTokenId, msg.sender, amount, data);
    }

    /// Stake funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// The stake is lost if either: the prediction period ends or the staker loses his private key (e.g. dies).
    /// Not recommended to stake after the oracle has finished, because funds may be (partially) lost (you could not unstake).
    function stakeCollateral(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralContractAddress, collateralTokenId, marketId, oracleId, amount, data);
        _mint(msg.sender, _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId), amount, data);
        emit StakeERC20Collateral(collateralContractAddress, collateralTokenId, msg.sender, amount, data);
    }

    /// If the oracle has not yet finished you can take funds back.
    function takeStakeBack(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, uint256 amount, bytes calldata data) external {
        require(oracleFinishedMap[oracleId], "too late");
        uint ourCollateralTokenId = _collateralSummaryTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        uint stakedCollateralTokenId = _collateralStakedTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        collateralTotalsMap[ourCollateralTokenId] = collateralTotalsMap[ourCollateralTokenId].sub(amount);
        collateralContractAddress.safeTransferFrom(address(this), msg.sender, ourCollateralTokenId, amount, data);
        collateralContractAddress.safeTransferFrom(address(this), msg.sender, stakedCollateralTokenId, amount, data);
        _burn(msg.sender, ourCollateralTokenId, amount);
        emit TakeBackERC20Collateral(collateralContractAddress, collateralTokenId, msg.sender, amount);
    }

    /// Anyone can register himself.
    /// Can be called both before or after the oracle finish. However registering after the finish is useless.
    function registerCustomer(uint64 marketId, bytes calldata data) external {
        uint256 conditionalTokenId = _conditionalTokenId(marketId, msg.sender);
        require(!conditionalTokensMap[conditionalTokenId], "customer already registered");
        conditionalTokensMap[conditionalTokenId] = true;
        _mint(msg.sender, conditionalTokenId, INITIAL_CUSTOMER_BALANCE, data);
        emit CustomerRegistered(msg.sender, marketId, data);
    }

    /// @dev Called by the oracle owner for reporting results of conditions.
    function reportNumerator(uint64 oracleId, address customer, uint256 numerator) external
        _isOracle(oracleId)
    {
        _updateNumerator(oracleId, numerator, customer);
        emit ReportedNumerator(oracleId, customer, numerator);
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

    /// Transfer to `msg.sender` the collateral ERC-20 token
    /// accordingly to the score of `condition` in the marketId by the oracle.
    /// After this function is called, it becomes impossible to transfer the corresponding conditional token of `msg.sender`
    /// (to prevent its repeated withdraw).
    function withdrawCollateral(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, address to, address condition, bytes calldata data) external {
        require(oracleFinishedMap[oracleId], "too early"); // to prevent the denominator or the numerators change meantime
        uint256 collateralBalance = _initialCollateralBalanceOf(collateralContractAddress, collateralTokenId, marketId, oracleId, msg.sender, condition);
        uint256 conditionalTokenId = _conditionalTokenId(marketId, condition);
        require(!redeemActivatedMap[msg.sender][oracleId][conditionalTokenId], "Already redeemed.");
        redeemActivatedMap[msg.sender][oracleId][conditionalTokenId] = true;
        userUsedRedeemMap[msg.sender][conditionalTokenId] = true;
        // _burn(msg.sender, conditionalTokenId, conditionalBalance); // Burning it would break using the same token for multiple outcomes.
        collateralContractAddress.safeTransferFrom(address(this), to, collateralTokenId, collateralBalance, data); // last to prevent reentrancy attack
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
        external
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
        external
    {
        for(uint i = 0; i < ids.length; ++i) {
            _checkTransferAllowed(ids[i], from);
        }
        _baseSafeBatchTransferFrom(from, to, ids, values, data);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns(bytes4) {
        return this.onERC1155Received.selector; // to accept transfers
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external returns(bytes4) {
        return bytes4(0); // We should never receive batch transfers.
    }

    // Getters //

    function oracleOwner(uint64 oracleId) public view returns (address) {
        return oracleOwnersMap[oracleId];
    }

    function isOracleFinished(uint64 oracleId) public view returns (bool) {
        return oracleFinishedMap[oracleId];
    }

    function payoutNumerator(uint64 marketId, address customer) public view returns (uint256) {
        return payoutNumeratorsMap[marketId][customer];
    }

    function payoutDenominator(uint64 marketId) public view returns (uint256) {
        return payoutDenominatorMap[marketId];
    }

    function isConditionalToken(uint256 tokenId) public view returns (bool) {
        return conditionalTokensMap[tokenId];
    }

    /// @param hash should be a result of `_collateralSummaryTokenId()`.
    function collateralTotal(uint256 hash) public view returns (uint256) {
        collateralTotalsMap[hash];
    }

    function isRedeemActivated(address holder, uint64 oracleId, uint256 conditionalTokenId) public view returns (bool) {
        return redeemActivatedMap[holder][oracleId][conditionalTokenId];
    }

    function isConditonalLocked(address holder, uint256 conditionalTokenId) public view returns (bool) {
        return userUsedRedeemMap[holder][conditionalTokenId];
    }

    // Internal //

    function _initialCollateralBalanceOf(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, address user, address condition) internal view
        returns (uint256)
    {
        uint256 numerator = payoutNumeratorsMap[oracleId][condition];
        uint256 denominator = payoutDenominatorMap[oracleId];
        uint256 conditonalBalance = balanceOf(user, _conditionalTokenId(marketId, condition));
        uint ourCollateralTokenId = _collateralSummaryTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        uint256 collateralTotalBalance = collateralTotalsMap[ourCollateralTokenId];
        // Rounded to below for no out-of-funds:
        int128 marketIdShare = ABDKMath64x64.divu(conditonalBalance, INITIAL_CUSTOMER_BALANCE);
        int128 rewardShare = ABDKMath64x64.divu(numerator, denominator);
        return marketIdShare.mul(rewardShare).mulu(collateralTotalBalance);
    }

    function _conditionalTokenId(uint64 marketId, address condition) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_CONDITIONAL), marketId, condition)));
    }

    function _collateralStakedTokenId(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_STAKED), collateralContractAddress, collateralTokenId, marketId, oracleId)));
    }

    function _collateralSummaryTokenId(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(TokenKind.TOKEN_SUMMARY), collateralContractAddress, collateralTokenId, marketId, oracleId)));
    }

    function _collateralIn(IERC1155 collateralContractAddress, uint256 collateralTokenId, uint64 marketId, uint64 oracleId, uint256 amount, bytes memory data) private {
        uint ourCollateralTokenId = _collateralSummaryTokenId(collateralContractAddress, collateralTokenId, marketId, oracleId);
        collateralTotalsMap[ourCollateralTokenId] = collateralTotalsMap[ourCollateralTokenId].add(amount);
        collateralContractAddress.safeTransferFrom(msg.sender, address(this), collateralTokenId, amount, data); // last against reentrancy attack
    }

    function _checkTransferAllowed(uint256 id, address from) internal view returns (bool) {
        require(!userUsedRedeemMap[from][id], "You can't trade conditional tokens after redeem.");
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

        _balances[id][from] = _balances[id][from].sub(value);
        _balances[id][to] = value.add(_balances[id][to]);

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

            _balances[id][from] = _balances[id][from].sub(value);
            _balances[id][to] = value.add(_balances[id][to]);
        }

        emit TransferBatch(msg.sender, from, to, ids, values);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, values, data);
    }

    function _updateNumerator(uint64 oracleId, uint256 numerator, address customer) private {
        payoutDenominatorMap[oracleId] = payoutDenominatorMap[oracleId].add(numerator).sub(payoutNumeratorsMap[oracleId][customer]);
        payoutNumeratorsMap[oracleId][customer] = numerator;
    }

    modifier _isOracle(uint64 oracleId) {
        require(oracleOwnersMap[oracleId] == msg.sender, "Not the oracle owner.");
        _;
    }
}
