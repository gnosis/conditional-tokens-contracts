pragma solidity ^0.5.1;
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";

/// We have four kinds of ERC-1155 token ID
/// - a combination of market ID, collateral address, and customer address (conditional tokens);
/// - a combination of TOKEN_DONATED and a collateral address (donated collateral tokens)
/// - a combination of TOKEN_STAKED and collateral address (staked collateral tokens)
/// - a store of already redeemed but not withdrawn collateral
contract ConditionalTokensMany is ERC1155 {
    // TODO: ERC-1155 collateral.
    // TODO: Getters.

    using ABDKMath64x64 for int128;

    enum CollateralKind { TOKEN_CONDITIONAL, TOKEN_DONATED, TOKEN_STAKED, TOKEN_REDEEMED }

    uint constant INITIAL_CUSTOMER_BALANCE = 1000 * 10**18; // an arbitrarily choosen value

    event MarketCreated(address oracle, uint64 marketId);

    event OutcomeCreated(address oracle, uint64 outcomeId);

    event CustomerRegistered(
        address customer,
        uint64 market,
        bytes data
    );

    event DonateERC20Collateral(
        IERC20 indexed collateralToken,
        address sender,
        uint256 amount,
        bytes data
    );

    event StakeERC20Collateral(
        IERC20 indexed collateralToken,
        address sender,
        uint256 amount,
        bytes data
    );

    event TakeBackERC20Collateral(
        IERC20 indexed collateralToken,
        address sender,
        uint256 amount,
        bytes data
    );

    event ReportedNumerator(
        uint64 indexed outcomeId,
        address customer,
        uint256 numerator
    );

    event ReportedNumeratorsBatch(
        uint64 indexed outcomeId,
        address[] addresses,
        uint256[] numerators
    );

    event OutcomeFinished(address indexed oracle);

    event RedeemCalculated(
        address customer,
        IERC20 indexed collateralToken,
        uint64 indexed market,
        uint64 indexed outcome,
        address tokenCustomer,
        uint payout
    );

    event CollateralWithdrawn(
        IERC20 collateralToken,
        uint64 market,
        uint64 outcome,
        address customer,
        uint256 amount
    );
    
    uint64 private maxId;

    /// Mapping from outcome to oracle.
    mapping(uint64 => address) public oracles;
    /// Whether an oracle finished its work.
    mapping(uint64 => bool) public outcomeFinished;
    /// Mapping (market => (customer => numerator)) for payout numerators.
    mapping(uint64 => mapping(address => uint256)) public payoutNumerators;
    /// Mapping (market => denominator) for payout denominators.
    mapping(uint64 => uint) public payoutDenominator;
    /// All conditonal tokens,
    mapping(uint256 => bool) public conditionalTokens;
    /// Total collaterals per market and outcome: collateral => (market => (outcome => total))
    mapping(uint256 => uint256) public collateralTotals;
    /// If a given conditional was already redeemed.
    mapping(address => mapping(uint64 => mapping(uint256 => bool))) public redeemActivated; // TODO: hash instead?
    /// The user lost the right to transfer conditional tokens: (user => (conditionalToken => bool)).
    mapping(address => mapping(uint256 => bool)) public userUsedRedeem;

    /// Register ourselves as an oracle for a new market.
    function createMarket() external {
        uint64 marketId = maxId++;
        emit MarketCreated(msg.sender, marketId);
    }

    function createOutcome() external {
        uint64 outcomeId = maxId++;
        oracles[outcomeId] = msg.sender;
        emit OutcomeCreated(msg.sender, outcomeId);
    }

    /// Donate funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// Not recommended to donate after any oracle has finished, because funds may be (partially) lost.
    function donate(IERC20 collateralToken, uint64 market, uint64 outcome, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralToken, market, outcome, amount);
        _mint(msg.sender, _collateralDonatedTokenId(collateralToken, market, outcome), amount, data);
        emit DonateERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    /// Donate funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// The stake is lost if either: the prediction period ends or the staker loses his private key (e.g. dies)
    /// Not recommended to stake after any oracle has finished, because funds may be (partially) lost (and you could not unstake).
    function stakeCollateral(IERC20 collateralToken, uint64 market, uint64 outcome, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralToken, market, outcome, amount);
        _mint(msg.sender, _collateralStakedTokenId(collateralToken, market, outcome), amount, data);
        emit StakeERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    function takeStakeBack(IERC20 collateralToken, uint64 market, uint64 outcome, uint256 amount, bytes calldata data) external {
        require(outcomeFinished[outcome], "too late");
        uint tokenId = _collateralStakedTokenId(collateralToken, market, outcome);
        collateralTotals[tokenId] = collateralTotals[tokenId].sub(amount);
        require(collateralToken.transfer(msg.sender, amount), "cannot transfer");
        _burn(msg.sender, tokenId, amount);
        emit TakeBackERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    /// Anyone can register anyone. Usually a customer registers himself or else an oracle may register him.
    /// Can be called both before or after the oracle finish. However registering after the finish is useless.
    function registerCustomer(uint64 market, address customer, bytes calldata data) external {
        uint256 conditionalTokenId = _conditionalTokenId(market, customer);
        require(!conditionalTokens[conditionalTokenId], "customer already registered");
        conditionalTokens[conditionalTokenId] = true;
        _mint(customer, conditionalTokenId, INITIAL_CUSTOMER_BALANCE, data);
        emit CustomerRegistered(customer, market, data);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 outcomeId, address customer, uint256 numerator) external
        _isOracle(outcomeId)
    {
        _updateNumerator(outcomeId, numerator, customer);
        emit ReportedNumerator(outcomeId, customer, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 outcomeId, address[] calldata addresses, uint256[] calldata numerators) external
        _isOracle(outcomeId)
    {
        require(addresses.length == numerators.length, "Length mismatch.");
        for (uint i = 0; i < addresses.length; ++i) {
            _updateNumerator(outcomeId, numerators[i], addresses[i]);
        }
        emit ReportedNumeratorsBatch(outcomeId, addresses, numerators);
    }

    function finishOutcome(uint64 outcomeId) external
        _isOracle(outcomeId)
    {
        outcomeFinished[outcomeId] = true;
        emit OutcomeFinished(msg.sender);
    }

    function activateRedeem(IERC20 collateralToken, uint64 market, uint64 outcome, address tokenCustomer, bytes calldata data) external {
        require(outcomeFinished[outcome], "too early"); // to prevent the denominator or the numerators change meantime
        uint256 collateralBalance = _initialCollateralBalanceOf(collateralToken, market, outcome, msg.sender, tokenCustomer);
        uint256 conditionalTokenId = _conditionalTokenId(market, tokenCustomer);
        require(!redeemActivated[msg.sender][outcome][conditionalTokenId], "Already redeemed.");
        redeemActivated[msg.sender][outcome][conditionalTokenId] = true;
        userUsedRedeem[msg.sender][conditionalTokenId] = true;
        uint256 redeemedTokenId = _collateralRedeemedTokenId(collateralToken, market, outcome);
        // _burn(msg.sender, conditionalTokenId, conditionalBalance); // Burning it would break using the same token for multiple outcomes.
        _mint(msg.sender, redeemedTokenId, collateralBalance, data);
        emit RedeemCalculated(msg.sender, collateralToken, market, outcome, tokenCustomer, collateralBalance);
    }

    function withdrawCollateral(IERC20 collateralToken, uint64 market, uint64 outcome, address customer, uint256 amount) external {
        uint256 redeemedTokenId = _collateralRedeemedTokenId(collateralToken, market, outcome);
        _burn(msg.sender, redeemedTokenId, amount);
        emit CollateralWithdrawn(collateralToken, market, outcome, customer, amount);
        collateralToken.transfer(customer, amount); // last to prevent reentrancy attack
    }

    function initialCollateralBalanceOf(IERC20 collateralToken, uint64 market, uint64 outcome, address customer, address tokenCustomer) external view returns (uint256) {
        return _initialCollateralBalanceOf(collateralToken, market, outcome, customer, tokenCustomer);
    }

    // Disallow transfers of conditional tokens after redeem to prevent "gathering" them before redeeming each outcome.
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

    // Disallow transfers of conditional tokens after redeem to prevent "gathering" them before redeeming each outcome.
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

    function _initialCollateralBalanceOf(IERC20 collateralToken, uint64 market, uint64 outcome, address customer, address tokenCustomer) internal view
        returns (uint256)
    {
        uint256 numerator = payoutNumerators[outcome][tokenCustomer];
        uint256 denominator = payoutDenominator[outcome];
        uint256 conditonalBalance = balanceOf(customer, _conditionalTokenId(market, tokenCustomer));
        uint tokenId = _collateralStakedTokenId(collateralToken, market, outcome);
        uint256 collateralTotalBalance = collateralTotals[tokenId];
        // Rounded to below for no out-of-funds:
        int128 marketShare = ABDKMath64x64.divu(conditonalBalance, INITIAL_CUSTOMER_BALANCE);
        int128 rewardShare = ABDKMath64x64.divu(numerator, denominator);
        return marketShare.mul(rewardShare).mulu(collateralTotalBalance);
    }

    function _conditionalTokenId(uint64 market, address tokenCustomer) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_CONDITIONAL), market, tokenCustomer)));
    }

    function _collateralDonatedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_DONATED), collateralToken, market, outcome)));
    }

    function _collateralStakedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_STAKED), collateralToken, market, outcome)));
    }

    function _collateralRedeemedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_REDEEMED), collateralToken, market, outcome)));
    }

    function _collateralIn(IERC20 collateralToken, uint64 market, uint64 outcome, uint256 amount) private {
        uint tokenId = _collateralStakedTokenId(collateralToken, market, outcome);
        collateralTotals[tokenId] = collateralTotals[tokenId].add(amount);
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "cannot transfer"); // last against reentrancy attack
    }

    function _checkTransferAllowed(uint256 id, address from) internal view returns (bool) {
        require(!userUsedRedeem[from][id], "You can't trade conditional tokens after redeem.");
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

    function _updateNumerator(uint64 outcomeId, uint256 numerator, address customer) private {
        payoutDenominator[outcomeId] = payoutDenominator[outcomeId].add(numerator).sub(payoutNumerators[outcomeId][customer]);
        payoutNumerators[outcomeId][customer] = numerator;
    }

    modifier _isOracle(uint64 outcomeId) {
        require(oracles[outcomeId] == msg.sender, "not the oracle");
        _;
    }
}
