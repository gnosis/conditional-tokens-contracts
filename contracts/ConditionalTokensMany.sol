pragma solidity ^0.5.1;
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";
import { CTHelpers } from "./CTHelpers.sol";

/// ERC-1155 token ID is a combination of market ID, collateral address, and customer address.
contract ConditionalTokensMany is ERC1155 {

    // TODO: Donors receive another token in return.
    // TODO: Allow to take donations back?!
    // TODO: Make impossible to claim funds before 100 years pass.

    uint constant INITIAL_CUSTOMER_BALANCE = 1000 * 10**18; // an arbitrarily choosen value

    event MarketCreated(address oracle, uint64 marketId);

    event DepositERC20Collateral(
        IERC20 indexed collateralToken,
        address sender,
        uint64 indexed market,
        uint256 amount,
        bytes data
    );

    event ReportedDenominator(
        uint64 indexed market,
        address indexed oracle,
        uint256 denominator
    );

    event ReportedNumerator(
        uint64 indexed market,
        address indexed oracle,
        address customer,
        uint128 numerator
    );

    event ReportedNumeratorsBatch(
        uint64 indexed market,
        address indexed oracle,
        address[] addresses,
        uint128[] numerators
    );

    event OracleFinished(address indexed oracle);

    event PayoutRedemption(
        address redeemer,
        IERC20 indexed collateralToken,
        uint64 indexed market,
        address customer,
        uint payout
    );

    uint64 private maxMarket;

    /// Mapping from market to oracle.
    mapping(uint64 => address) public oracles;
    /// Whether an oracle finished its work.
    mapping(address => bool) public oracleFinished;
    /// Mapping (market => (customer => numerator)) for payout numerators. Using uint128 prevents multiplication overflows.
    mapping(uint64 => mapping(address => uint128)) public payoutNumerators; // TODO: hash instead?
    /// Mapping (market => denominator) for payout denominators.
    mapping(uint64 => uint) public payoutDenominator;
    /// Total balance of conditional for a given market and collateral.
    mapping(uint256 => uint) public totalMarketBalances;

    /// Register ourselves as an oracle for a new market.
    function createMarket() external {
        uint64 marketId = maxMarket++;
        oracles[marketId] = msg.sender;
        emit MarketCreated(msg.sender, marketId);
    }

    /// Deposit funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    function deposit(IERC20 collateralToken, uint64 market, bytes calldata data) external payable {
        address oracle = oracles[market];
        require(!oracleFinished[oracle]);
        require(collateralToken.transferFrom(msg.sender, address(this), msg.value));
        emit DepositERC20Collateral(collateralToken, msg.sender, market, msg.value, data);
    }

    function registerCustomer(IERC20 collateralToken, uint64 market, bytes calldata data) external {
        totalMarketBalances[_collateralTokenId(market, collateralToken)] += INITIAL_CUSTOMER_BALANCE;
        _mint(msg.sender, _conditionalTokenId(market, collateralToken, msg.sender), INITIAL_CUSTOMER_BALANCE, data);
    }

    function reportDenominator(uint64 market, uint256 denominator) external {
        require(oracles[market] == msg.sender);
        payoutDenominator[market] = denominator;
        emit ReportedDenominator(market, msg.sender, denominator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 market, address customer, uint128 numerator) external {
        require(oracles[market] == msg.sender);
        payoutNumerators[market][customer] = numerator;
        emit ReportedNumerator(market, msg.sender, customer, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 market, address[] calldata addresses, uint128[] calldata numerators) external {
        require(oracles[market] == msg.sender);
        for (uint i = 0; i < addresses.length; ++i) {
            address customer = addresses[i];
            payoutNumerators[market][customer] = numerators[i];
        }
        emit ReportedNumeratorsBatch(market, msg.sender, addresses, numerators);
    }

    function finishOracle() external {
        oracleFinished[msg.sender] = true;
        emit OracleFinished(msg.sender);
    }

    function redeemPosition(IERC20 collateralToken, uint64 market, address customer) external {
        address oracle = oracles[market];
        require(oracleFinished[oracle]); // to prevent the denominator or the numerators change meantime
        uint256 amount = _collateralBalanceOf(collateralToken, market, customer);
        payoutNumerators[market][customer] = 0;
        emit PayoutRedemption(msg.sender, collateralToken, market, customer, amount);
        collateralToken.transfer(customer, amount); // last to prevent reentrancy attack
    }

    function collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) external view returns (uint256) {
        return _collateralBalanceOf(collateralToken, market, customer);
    }

    function _collateralTokenId(uint64 market, IERC20 collateralToken) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, collateralToken)));
    }

    function _conditionalTokenId(uint64 market, IERC20 collateralToken, address customer) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, collateralToken, customer)));
    }

    function _collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) internal view returns (uint256) {
        uint256 numerator = uint256(payoutNumerators[market][customer]);
        uint256 denominator = payoutDenominator[market];
        uint256 total = totalMarketBalances[_collateralTokenId(market, collateralToken)];
        uint256 customerBalance = balanceOf(customer, _conditionalTokenId(market, collateralToken, customer));
        // Rounded to below for no out-of-funds, no overflow because numerator is small:
        return customerBalance * numerator / denominator / total;
    }
}
