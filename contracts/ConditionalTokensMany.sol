pragma solidity ^0.5.1;
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";

/// We have four kinds of ERC-1155 token ID
/// - a combination of market ID, collateral address, and customer address (conditional tokens);
/// - a combination of TOKEN_DONATED and a collateral address (donated collateral tokens)
/// - a combination of TOKEN_STAKED and collateral address (staked collateral tokens)
/// - a store of already redeemed collateral
contract ConditionalTokensMany is ERC1155 {
    // TODO: ERC-1155 collateral.
    // TODO: Getters.
    // TODO: Oracle based (with quadratic upgradeable voting) recovery of lost accounts.

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
        address redeemer,
        IERC20 indexed collateralToken,
        uint64 indexed market,
        uint64 indexed outcome,
        address customer,
        uint payout
    );

    event CollateralWithdrawn(
        IERC20 collateralToken,
        uint64 market,
        uint64 outcome,
        address customer,
        uint256 amount
    );
    
    uint64 private maxId; // FIXME: will 64 bit be enough after 100 years?!

    /// Mapping from outcome to oracle.
    mapping(uint64 => address) public oracles;
    /// Whether an oracle finished its work.
    mapping(uint64 => bool) public outcomeFinished;
    /// Mapping (market => (customer => numerator)) for payout numerators.
    mapping(uint64 => mapping(address => uint256)) public payoutNumerators; // TODO: hash instead?
    /// Mapping (market => denominator) for payout denominators.
    mapping(uint64 => uint) public payoutDenominator;
    /// All conditonal tokens,
    mapping(uint256 => bool) public conditionalTokens;
    /// Total collaterals per market and outcome: collateral => (market => (outcome => total))
    mapping(address => mapping(uint64 => mapping(uint64 => uint256))) collateralTotals; // TODO: hash instead?
    /// Total conditional market balances
    mapping(uint64 => uint256) marketTotalBalances; // TODO: hash instead?

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
        collateralTotals[address(collateralToken)][market][outcome] = collateralTotals[address(collateralToken)][market][outcome].sub(amount);
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
        marketTotalBalances[market] += INITIAL_CUSTOMER_BALANCE; // No chance of overflow.
        emit CustomerRegistered(customer, market, data);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 outcomeId, address customer, uint256 numerator) external
        _isOracle(outcomeId)
    {
        // TODO: duplicate code
        payoutDenominator[outcomeId] = payoutDenominator[outcomeId].add(numerator).sub(payoutNumerators[outcomeId][customer]);
        payoutNumerators[outcomeId][customer] = numerator;
        emit ReportedNumerator(outcomeId, customer, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 outcomeId, address[] calldata addresses, uint256[] calldata numerators) external
        _isOracle(outcomeId)
    {
        require(addresses.length == numerators.length, "length mismatch");
        for (uint i = 0; i < addresses.length; ++i) {
            address customer = addresses[i];
            uint256 numerator = numerators[i];
            // TODO: duplicate code
            payoutDenominator[outcomeId] = payoutDenominator[outcomeId].add(numerator).sub(payoutNumerators[outcomeId][customer]);
            payoutNumerators[outcomeId][customer] = numerator;
        }
        emit ReportedNumeratorsBatch(outcomeId, addresses, numerators);
    }

    function finishOutcome(uint64 outcomeId) external
        _isOracle(outcomeId)
    {
        outcomeFinished[outcomeId] = true;
        emit OutcomeFinished(msg.sender);
    }

    function calculateRedeemAmount(IERC20 collateralToken, uint64 market, uint64 outcome, address customer, bytes calldata data) external {
        require(outcomeFinished[outcome], "too early"); // to prevent the denominator or the numerators change meantime
        (uint256 conditionalBalance, uint256 collateralBalance) =
            _collateralBalanceOf(collateralToken, market, outcome, customer);
        uint256 redeemedTokenId = _collateralRedeemedTokenId(collateralToken, market, outcome);
        uint256 conditionalTokenId = _conditionalTokenId(market, customer); // TODO: calculates the same in _collateralBalanceOf
        _mint(customer, redeemedTokenId, collateralBalance, data);
        _burn(customer, conditionalTokenId, conditionalBalance);
        emit RedeemCalculated(msg.sender, collateralToken, market, outcome, customer, collateralBalance); // TODO: Also return conditionalBalance?
    }

    function withdrawCollateral(IERC20 collateralToken, uint64 market, uint64 outcome, address customer, uint256 amount) external {
        uint256 redeemedTokenId = _collateralRedeemedTokenId(collateralToken, market, outcome);
        _burn(customer, redeemedTokenId, amount);
        emit CollateralWithdrawn(collateralToken, market, outcome, customer, amount);
        collateralToken.transfer(customer, amount); // last to prevent reentrancy attack
    }

    function collateralBalanceOf(IERC20 collateralToken, uint64 market, uint64 outcome, address customer) external view returns (uint256) {
        (, uint256 collateralBalance) = _collateralBalanceOf(collateralToken, market, outcome, customer);
        return collateralBalance;
    }

    function _collateralBalanceOf(IERC20 collateralToken, uint64 market, uint64 outcome, address customer) internal view
        returns (uint256 conditonalBalance, uint256 collateralBalance)
    {
        uint256 numerator = uint256(payoutNumerators[outcome][customer]);
        uint256 denominator = payoutDenominator[outcome];
        conditonalBalance = balanceOf(customer, _conditionalTokenId(market, customer));
        uint256 collateralTotalBalance = collateralTotals[address(collateralToken)][market][outcome];
        // Rounded to below for no out-of-funds:
        int128 marketShare = ABDKMath64x64.divu(conditonalBalance, marketTotalBalances[market]);
        int128 userShare = ABDKMath64x64.divu(numerator, denominator);
        collateralBalance = marketShare.mul(userShare).mulu(collateralTotalBalance);
    }

    function _conditionalTokenId(uint64 market, address customer) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_CONDITIONAL), market, customer)));
    }

    function _collateralStakedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_DONATED), collateralToken, market, outcome)));
    }

    function _collateralDonatedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_STAKED), collateralToken, market, outcome)));
    }

    function _collateralRedeemedTokenId(IERC20 collateralToken, uint64 market, uint64 outcome) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_REDEEMED), collateralToken, market, outcome)));
    }

    function _collateralIn(IERC20 collateralToken, uint64 market, uint64 outcome, uint256 amount) private {
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "cannot transfer");
        collateralTotals[address(collateralToken)][market][outcome] =
            collateralTotals[address(collateralToken)][market][outcome].add(amount);
    }

    modifier _isOracle(uint64 outcomeId) {
        require(oracles[outcomeId] == msg.sender, "not the oracle");
        _;
    }
}
