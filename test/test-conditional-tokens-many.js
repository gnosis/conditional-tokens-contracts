const ethSigUtil = require("eth-sig-util");

const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN, randomHex } = web3.utils;
const {
  getConditionId,
  getCollectionId,
  combineCollectionIds,
  getPositionId
} = require("../utils/id-helpers")(web3.utils);

const ConditionalTokensMany = artifacts.require("ConditionalTokensMany");
const ERC20Mintable = artifacts.require("MockCoin");

const wallet1 = new Wallet();
const wallet2 = new Wallet();

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
        const marketId1 = this.logs1.marketId;
        ({ logs: this.logs2 } = await this.conditionalTokens.createMarket());
        const marketId2 = this.logs2.marketId;
    });

      it("should emit an MarketCreated event", async function() {
        expect(marketId1).should.be.bignumber.equal("0");
        expect(marketId2).should.be.bignumber.equal("1");
        expectEvent.inLogs(this.logs, "MarketCreated", {
          oracle: accounts[0],
          marketId1
        });
        expectEvent.inLogs(this.logs, "MarketCreated", {
            oracle: accounts[0],
            marketId2
        });
      });

      it("should leave payout denominator unset", async function() {
        (
          await this.conditionalTokens.payoutDenominator(marketId1)
        ).should.be.bignumber.equal("0");
        (
          await this.conditionalTokens.payoutDenominator(marketId2)
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
