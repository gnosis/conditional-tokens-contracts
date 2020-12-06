pragma solidity ^0.5.1;
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "./ERC1155/ERC1155.sol";
import { CTHelpers } from "./CTHelpers.sol";

contract ConditionalTokens is ERC1155 {

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
        uint256 numerator
    );

    event ReportedNumeratorsBatch(
        uint64 indexed market,
        address indexed oracle,
        address[] addresses,
        uint256[] numerators
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
    mapping(uint64 => address) public markets;
    /// Whether an oracle finished its work.
    mapping(address => bool) public oracleFinished;
    /// Mapping (market => (customer => numerator)) for payout numerators.
    mapping(uint64 => mapping(address => uint)) public payoutNumerators; // TODO: hash instead?
    /// Mapping (market => denominator) for payout denominators.
    mapping(uint64 => uint) public payoutDenominator;

    /// Register ourselves as an oracle for a new market.
    function createMarket() external {
        uint64 marketId = maxMarket++;
        markets[marketId] = msg.sender;
        emit MarketCreated(msg.sender, marketId);
    }

    /// Deposit funds in a ERC20 token.
    /// First need to approve the contract to spend the token.
    /// FIXME: Be able to withdraw again after a new deposit.
    function deposit(IERC20 collateralToken, uint64 market, bytes calldata data) external payable {
        require(collateralToken.transferFrom(msg.sender, address(this), msg.value));
        emit DepositERC20Collateral(collateralToken, msg.sender, market, msg.value, data);
    }

    function reportDenominator(uint64 market, uint256 denominator) external {
        require(markets[market] == msg.sender);
        payoutDenominator[market] = denominator;
        emit ReportedDenominator(market, msg.sender, denominator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 market, address customer, uint256 numerator) external {
        require(markets[market] == msg.sender);
        payoutNumerators[market][customer] = numerator;
        emit ReportedNumerator(market, msg.sender, customer, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 market, address[] calldata addresses, uint256[] calldata numerators) external {
        require(markets[market] == msg.sender);
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
        // uint256 tokenId = _tokenId(market, collateralToken);
        address oracle = markets[market];
        require(oracleFinished[oracle]); // to prevent the denominator or the numerators change meantime
        uint256 amount = _collateralBalanceOf(collateralToken, market, customer);
        payoutNumerators[market][customer] = 0;
        emit PayoutRedemption(msg.sender, collateralToken, market, customer, amount);
        collateralToken.transfer(customer, amount); // last to prevent reentrancy attack
    }

    function collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) external view returns (uint256) {
        return _collateralBalanceOf(collateralToken, market, customer);
    }

    function _tokenId(uint64 market, IERC20 collateralToken) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, collateralToken)));
    }

    function _collateralBalanceOf(IERC20 collateralToken, uint64 market, address customer) internal view returns (uint256) {
        // uint256 tokenId = _tokenId(market, collateralToken);
        uint256 numerator = payoutNumerators[market][customer];
        uint256 denominator = payoutDenominator[market];
        uint256 total = balanceOf(customer, _tokenId(market, collateralToken));
        return total * numerator / denominator; // rounded to below for no out-of-funds
    }
}
