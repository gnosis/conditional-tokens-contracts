pragma solidity ^0.5.1;
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";
import { CTHelpers } from "./CTHelpers.sol";

/// We have three kinds of ERC-1155 token ID
/// - a combination of market ID, collateral address, and customer address (conditional tokens);
/// - a collateral address (donated collateral tokens)
/// - a combination of TOKEN_STAKED and collateral address (staked collateral tokens)
contract ConditionalTokensMany is ERC1155 {
    // TODO: ERC-1155 collateral.
    // TODO: Oracle based (with quadratic upgradeable voting) recovery of lost accounts.

    enum CollateralKind { TOKEN_STAKED }

    uint constant INITIAL_CUSTOMER_BALANCE = 1000 * 10**18; // an arbitrarily choosen value

    event MarketCreated(address oracle, uint64 marketId);

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

    uint64 private maxMarket; // FIXME: will 64 bit be enough after 100 years?!

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
    /// All customers
    mapping(address => bool) public customers;

    /// Register ourselves as an oracle for a new market.
    function createMarket() external {
        uint64 marketId = maxMarket++;
        oracles[marketId] = msg.sender;
        emit MarketCreated(msg.sender, marketId);
    }

    /// Donate funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// Not recommended to donate after any oracle has finished, because funds may be (partially) lost.
    function donate(IERC20 collateralToken, uint64 market, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralToken, amount);
        _mint(msg.sender, _collateralDonatedTokenId(collateralToken, market), amount, data);
        emit DonateERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    /// Donate funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// The stake is lost if either: the prediction period ends or the staker loses his private key (e.g. dies)
    /// Not recommended to stake after any oracle has finished, because funds may be (partially) lost (and you could not unstake).
    function stakeCollateral(IERC20 collateralToken, uint64 market, uint256 amount, bytes calldata data) external {
        _collateralIn(collateralToken, amount);
        _mint(msg.sender, _collateralStakedTokenId(collateralToken, market), amount, data);
        emit StakeERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    function takeStakeBack(IERC20 collateralToken, uint64 market, uint256 amount, bytes calldata data) external {
        address oracle = oracles[market];
        require(oracleFinished[oracle], "too late");
        uint tokenId = _collateralStakedTokenId(collateralToken, market);
        require(balanceOf(msg.sender, tokenId) >= amount, "not enough balance");
        require(collateralToken.transfer(msg.sender, amount), "cannot transfer");
        _burn(msg.sender, tokenId, amount);
        emit TakeBackERC20Collateral(collateralToken, msg.sender, amount, data);
    }

    // FIXME: It's possible to register a customer once for all markets at once.
    function registerCustomer(uint64 market, bytes calldata data) external {
        require(!customers[msg.sender], "customer already registered");
        customers[msg.sender] = true;
        uint256 conditionalTokenId = _conditionalTokenId(market, msg.sender);
        totalMarketBalances[conditionalTokenId] += INITIAL_CUSTOMER_BALANCE;
        _mint(msg.sender, conditionalTokenId, INITIAL_CUSTOMER_BALANCE, data);
        emit CustomerRegistered(msg.sender, market, data);
    }

    function reportDenominator(uint64 market, uint256 denominator) external
        _isOracle(market)
    {
        require(oracles[market] == msg.sender, "not the oracle");
        payoutDenominator[market] = denominator;
        emit ReportedDenominator(market, msg.sender, denominator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 market, address customer, uint128 numerator) external
        _isOracle(market)
    {
        payoutNumerators[market][customer] = numerator;
        emit ReportedNumerator(market, msg.sender, customer, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 market, address[] calldata addresses, uint128[] calldata numerators) external
        _isOracle(market)
    {
        require(addresses.length == numerators.length, "length mismatch");
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
        require(oracleFinished[oracle], "too early"); // to prevent the denominator or the numerators change meantime
        uint256 amount = _collateralBalanceOf(collateralToken, market, customer);
        payoutNumerators[market][customer] = 0;
        emit PayoutRedemption(msg.sender, collateralToken, market, customer, amount);
        collateralToken.transfer(customer, amount); // last to prevent reentrancy attack
    }

    function collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) external view returns (uint256) {
        return _collateralBalanceOf(collateralToken, market, customer);
    }

    function _collateralTokenId(IERC20 collateralToken, uint64 market) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, collateralToken)));
    }

    function _conditionalTokenId(uint64 market, address customer) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, customer)));
    }

    function _collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) internal view returns (uint256) {
        uint256 numerator = uint256(payoutNumerators[market][customer]);
        uint256 denominator = payoutDenominator[market];
        uint256 total = totalMarketBalances[_collateralTokenId(collateralToken, market)];
        uint256 customerBalance = balanceOf(customer, _conditionalTokenId(market, customer));
        // Rounded to below for no out-of-funds, no overflow because numerator is small:
        return customerBalance * numerator / denominator / total;
    }

    function _collateralStakedTokenId(IERC20 collateralToken, uint64 market) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, market)));
    }

    function _collateralDonatedTokenId(IERC20 collateralToken, uint64 market) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint8(CollateralKind.TOKEN_STAKED), collateralToken, market)));
    }

    function _collateralIn(IERC20 collateralToken, uint256 amount) private {
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "cannot transfer");
    }

    modifier _isOracle(uint64 market) {
        require(oracles[market] == msg.sender, "not the oracle");
        _;
    }
}
