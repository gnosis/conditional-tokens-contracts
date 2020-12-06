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
        address recipient,
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
        address address_,
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
        address address_,
        uint payout
    );

    uint64 private maxMarket;

    /// Mapping from market to oracle.
    mapping(uint64 => address) public markets;

    mapping(address => bool) public oracleFinished;

    // TODO: The following two are mappings from markets

    /// Mapping key is an condition ID. Value represents numerators of the payout vector associated with the condition. This array is initialized with a length equal to the outcome slot count. E.g. Condition with 3 outcomes [A, B, C] and two of those correct [0.5, 0.5, 0]. In Ethereum there are no decimal values, so here, 0.5 is represented by fractions like 1/2 == 0.5. That's why we need numerator and denominator values. Payout numerators are also used as a check of initialization. If the numerators array is empty (has length zero), the condition was not created/prepared. See getOutcomeSlotCount.
    mapping(uint64 => mapping(address => uint)) public payoutNumerators; // TODO: hash instead?
    /// Denominator is also used for checking if the condition has been resolved. If the denominator is non-zero, then the condition has been resolved.
    mapping(uint64 => uint) public payoutDenominator;

    /// Register ourselves as an oracle for a new market.
    function createMarket() external {
        uint64 marketId = maxMarket++;
        markets[marketId] = msg.sender;
        emit MarketCreated(msg.sender, marketId);
    }

    /// First need to approve the contract to spend the token.
    function deposit(IERC20 collateralToken, uint64 market, address recipient, uint256 amount, bytes calldata data) external {
        require(collateralToken.transferFrom(msg.sender, address(this), amount));
        _mint(recipient, _tokenId(market, collateralToken), amount, data);
        emit DepositERC20Collateral(collateralToken, msg.sender, market, recipient, amount, data);
    }

    function reportDenominator(uint64 market, uint256 denominator) external {
        require(markets[market] == msg.sender);
        payoutDenominator[market] = denominator;
        emit ReportedDenominator(market, msg.sender, denominator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumerator(uint64 market, address address_, uint256 numerator) external {
        require(markets[market] == msg.sender);
        payoutNumerators[market][address_] = numerator;
        emit ReportedNumerator(market, msg.sender, address_, numerator);
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    function reportNumeratorsBatch(uint64 market, address[] calldata addresses, uint256[] calldata numerators) external {
        require(markets[market] == msg.sender);
        for (uint i = 0; i < addresses.length; ++i) {
            address address_ = addresses[i];
            payoutNumerators[market][address_] = numerators[i];
        }
        emit ReportedNumeratorsBatch(market, msg.sender, addresses, numerators);
    }

    function finishOracle() external {
        oracleFinished[msg.sender] = true;
        emit OracleFinished(msg.sender);
    }

    // TODO: Partial redeem.
    // TODO: Function to calculate balance.
    // FIXME: What to do if the denominator or the numerators change meantime?
    function redeemPositions(IERC20 collateralToken, uint64 market, address address_) external {
        // uint256 tokenId = _tokenId(market, collateralToken);
        address oracle = markets[market];
        require(oracleFinished[oracle]);
        uint256 numerator = payoutNumerators[market][address_];
        uint256 denominator = payoutDenominator[market];
        uint256 total = balanceOf(address_, _tokenId(market, collateralToken));
        uint256 amount = total * numerator / denominator; // rounded to below for no out-of-funds
        payoutNumerators[market][address_] = 0;
        emit PayoutRedemption(msg.sender, collateralToken, market, address_, amount);
        collateralToken.transfer(address_, amount); // last to prevent reentrancy attack
    }

    function _tokenId(uint64 market, IERC20 collateralToken) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(market, collateralToken)));
    }
}
