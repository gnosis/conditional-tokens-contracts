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

contract("ConditionalTokensMany", function(accounts) {
  const [
    minter,
    oracle,
    notOracle,
    eoaTrader,
    fwdExecutor,
    safeExecutor,
    counterparty
  ] = accounts;

  beforeEach("initiate token contracts", async function() {
    this.conditionalTokens = await ConditionalTokensMany.new();
    // this.collateral = await ERC20Mintable.new(); // TODO: Check multiple collaterals
    // this.collateral.mint(donor, "10000");
  });

  describe("createMarket", function() {
    context("with valid parameters", function() {
      beforeEach(async function() {
        this.oracle1 = accounts[0];
        this.customer1 = accounts[1];
        this.customer2 = accounts[2];
        ({ logs: this.logs1 } = await this.conditionalTokens.createMarket());
        this.market1 = this.logs1[0].args.marketId;
        ({ logs: this.logs2 } = await this.conditionalTokens.createMarket());
        this.market2 = this.logs2[0].args.marketId;
      });

      it("should emit a MarketCreated event", function() {
        this.market1.should.be.bignumber.equal("0");
        this.market2.should.be.bignumber.equal("1");
        expectEvent.inLogs(this.logs1, "MarketCreated", {
          oracle: this.oracle1,
          marketId: this.market1
        });
        expectEvent.inLogs(this.logs2, "MarketCreated", {
          oracle: this.oracle1,
          marketId: this.market2
        });
      });

      it("should leave payout denominator unset", async function() {
        (
          await this.conditionalTokens.payoutDenominator(this.market1)
        ).should.be.bignumber.equal("0");
        (
          await this.conditionalTokens.payoutDenominator(this.market2)
        ).should.be.bignumber.equal("0");
      });

      it("should not be able to register the same customer more than once for the same market", async function() {
        await this.conditionalTokens.registerCustomer(this.market1, [], {
          from: this.customer1
        });
        await expectRevert(
          this.conditionalTokens.registerCustomer(this.market1, [], {
            from: this.customer1
          }),
          "customer already registered"
        );
        // TODO: Check that can register the same customer for different markets.
      });

      it("checking the math", async function() {
        const collateral = await this.conditionalTokens.registerCustomer(
          this.market1,
          [],
          {
            from: this.customer1
          }
        );
        await this.conditionalTokens.registerCustomer(this.market1, [], {
          from: this.customer2
        });
        await this.conditionalTokens.registerCustomer(this.market2, [], {
          from: this.customer1
        });
        await this.conditionalTokens.registerCustomer(this.market2, [], {
          from: this.customer2
        });

        await this.conditionalTokens.reportDenominator(this.market1, toBN("3"));
        await this.conditionalTokens.reportNumerator(
          this.market1,
          this.customer1,
          toBN("20")
        );
        await this.conditionalTokens.reportNumerator(
          this.market1,
          this.customer2,
          toBN("10")
        );
        await this.conditionalTokens.finishMarket(this.market1);
        await this.conditionalTokens.reportDenominator(this.market2, toBN("3"));
        await this.conditionalTokens.reportNumerator(
          this.market2,
          this.customer1,
          toBN("20")
        );
        await this.conditionalTokens.reportNumerator(
          this.market2,
          this.customer2,
          toBN("10")
        );
        await this.conditionalTokens.finishMarket(this.market2);

        // await collateralBalanceOf(collateralToken, market1, customer1)
        // TODO
      });
    });
  });
});
