const ethSigUtil = require("eth-sig-util");

const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN, randomHex } = web3.utils;
const { accounts } = web3.eth;
const {
  getConditionId,
  getCollectionId,
  combineCollectionIds,
  getPositionId
} = require("../utils/id-helpers")(web3.utils);

const ConditionalTokensMany = artifacts.require("ConditionalTokensMany");
const ERC20Mintable = artifacts.require("MockCoin");

const wallet1 = accounts.wallet.create();
const wallet2 = accounts.wallet.create();

contract("ConditionalTokens", function(accounts) {
  const [
    minter,
    oracle,
    notOracle,
    eoaTrader,
    fwdExecutor,
    safeExecutor,
    counterparty
  ] = accounts;

  beforeEach("deploy ConditionalTokens", async function() {
    this.conditionalTokens = await ConditionalTokensMany.new();
  });

  describe("createMarket", function() {
    context("with valid parameters", function() {
      beforeEach(async function() {
        ({ logs: this.logs1 } = await this.conditionalTokens.createMarket());
        this.marketId1 = this.logs1[0].args.marketId;
        ({ logs: this.logs2 } = await this.conditionalTokens.createMarket());
        this.marketId2 = this.logs2[0].args.marketId;
      });

      it("should emit an MarketCreated event", function() {
        this.marketId1.should.be.bignumber.equal("0");
        this.marketId2.should.be.bignumber.equal("1");
        expectEvent.inLogs(this.logs1, "MarketCreated", {
          oracle: accounts[0],
          marketId: this.marketId1
        });
        expectEvent.inLogs(this.logs2, "MarketCreated", {
          oracle: accounts[0],
          marketId: this.marketId2
        });
      });

      it("should leave payout denominator unset", async function() {
        (
          await this.conditionalTokens.payoutDenominator(this.marketId1)
        ).should.be.bignumber.equal("0");
        (
          await this.conditionalTokens.payoutDenominator(this.marketId2)
        ).should.be.bignumber.equal("0");
      });

      //   it("should not be able to prepare the same condition more than once", async function() {
      //     await expectRevert(
      //       this.conditionalTokens.prepareCondition(
      //         oracle,
      //         questionId,
      //         outcomeSlotCount
      //       ),
      //       "condition already prepared"
      //     );
      //   });
    });
  });
});
