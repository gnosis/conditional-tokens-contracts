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
    this.conditionalTokens = await ConditionalTokens.new();
  });

  describe("prepareCondition", function() {
    context("with valid parameters", function() {
      const questionId = randomHex(32);
      const outcomeSlotCount = toBN(256);

      const conditionId = getConditionId(oracle, questionId, outcomeSlotCount);

      beforeEach(async function() {
        ({ logs: this.logs } = await this.conditionalTokens.prepareCondition(
          oracle,
          questionId,
          outcomeSlotCount
        ));
      });

      it("should emit an ConditionPreparation event", async function() {
        expectEvent.inLogs(this.logs, "ConditionPreparation", {
          conditionId,
          oracle,
          questionId,
          outcomeSlotCount
        });
      });

      it("should leave payout denominator unset", async function() {
        (
          await this.conditionalTokens.payoutDenominator(conditionId)
        ).should.be.bignumber.equal("0");
      });

      it("should not be able to prepare the same condition more than once", async function() {
        await expectRevert(
          this.conditionalTokens.prepareCondition(
            oracle,
            questionId,
            outcomeSlotCount
          ),
          "condition already prepared"
        );
      });
    });
  });
});
