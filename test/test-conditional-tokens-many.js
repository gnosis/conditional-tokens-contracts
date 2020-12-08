const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN } = web3.utils;

const ConditionalTokensMany = artifacts.require("ConditionalTokensMany");
const ERC20Mintable = artifacts.require("MockCoin");

contract("ConditionalTokensMany", function(accounts) {
  const [oracle1, customer1, customer2, donor1] = accounts;

  beforeEach("initiate token contracts", async function() {
    this.conditionalTokens = await ConditionalTokensMany.new();
    this.collateral = await ERC20Mintable.new(); // TODO: Check multiple collaterals
    this.collateral.mint(donor1, "10000000");
  });

  describe("createMarket", function() {
    // TODO: rename
    context("with valid parameters", function() {
      beforeEach(async function() {
        ({ logs: this.logs1 } = await this.conditionalTokens.createMarket());
        this.market1 = this.logs1[0].args.marketId;
        ({ logs: this.logs2 } = await this.conditionalTokens.createMarket());
        this.market2 = this.logs2[0].args.marketId;
        ({ logs: this.logs3 } = await this.conditionalTokens.createOutcome());
        this.outcome1 = this.logs3[0].args.outcomeId;
        ({ logs: this.logs4 } = await this.conditionalTokens.createOutcome());
        this.outcome2 = this.logs4[0].args.outcomeId;
      });

      it("should emit a MarketCreated event", function() {
        this.market1.should.be.bignumber.equal("0");
        this.market2.should.be.bignumber.equal("1");
        expectEvent.inLogs(this.logs1, "MarketCreated", {
          oracle: oracle1,
          marketId: this.market1
        });
        expectEvent.inLogs(this.logs2, "MarketCreated", {
          oracle: oracle1,
          marketId: this.market2
        });
        // TODO: Check "OutcomeCreated"
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
          from: customer1
        });
        await expectRevert(
          this.conditionalTokens.registerCustomer(this.market1, [], {
            from: customer1
          }),
          "customer already registered"
        );
        // TODO: Check that can register the same customer for different markets.
      });

      it("checking the math", async function() {
        await this.conditionalTokens.registerCustomer(this.market1, [], {
          from: customer1
        });
        await this.conditionalTokens.registerCustomer(this.market1, [], {
          from: customer2
        });
        await this.conditionalTokens.registerCustomer(this.market2, [], {
          from: customer1
        });
        await this.conditionalTokens.registerCustomer(this.market2, [], {
          from: customer2
        });
        const NUMBER_CUSTOMERS1 = toBN("2");
        const NUMBER_CUSTOMERS2 = toBN("2");

        await this.collateral.approve(
          this.conditionalTokens.address,
          "1000000000000" /* a big number */,
          { from: donor1 }
        );
        // TODO: Test more than one market per outcome.
        await this.conditionalTokens.donate(
          this.collateral.address,
          this.market1,
          this.outcome1,
          "400",
          [],
          { from: donor1 }
        );
        await this.conditionalTokens.stakeCollateral(
          this.collateral.address,
          this.market1,
          this.outcome1,
          "600",
          [],
          { from: donor1 }
        );
        await this.conditionalTokens.donate(
          this.collateral.address,
          this.market2,
          this.outcome2,
          "4000",
          [],
          { from: donor1 }
        );
        await this.conditionalTokens.stakeCollateral(
          this.collateral.address,
          this.market2,
          this.outcome2,
          "6000",
          [],
          { from: donor1 }
        );
        const TOTAL_COLLATERAL1 = toBN("1000");
        const TOTAL_COLLATERAL2 = toBN("10000");

        await this.conditionalTokens.reportNumerator(
          this.outcome1,
          customer1,
          toBN("20")
        );
        await this.conditionalTokens.reportNumerator(
          this.outcome1,
          customer2,
          toBN("10")
        );
        await this.conditionalTokens.finishOutcome(this.outcome1);

        await this.conditionalTokens.reportNumerator(
          this.outcome2,
          customer1,
          toBN("90")
        );
        await this.conditionalTokens.reportNumerator(
          this.outcome2,
          customer2,
          toBN("10")
        );
        await this.conditionalTokens.finishOutcome(this.outcome1);

        (
          await this.conditionalTokens.collateralBalanceOf(
            this.collateral.address,
            this.market1,
            this.outcome1,
            customer1
          )
        )
          .sub(
            TOTAL_COLLATERAL1.mul(toBN("20"))
              .div(toBN("30"))
              .div(NUMBER_CUSTOMERS1)
          )
          .abs()
          .should.be.bignumber.below(toBN("2"));
        (
          await this.conditionalTokens.collateralBalanceOf(
            this.collateral.address,
            this.market1,
            this.outcome1,
            customer2
          )
        )
          .sub(
            TOTAL_COLLATERAL1.mul(toBN("10"))
              .div(toBN("30"))
              .div(NUMBER_CUSTOMERS1)
          )
          .abs()
          .should.be.bignumber.below(toBN("2"));
        (
          await this.conditionalTokens.collateralBalanceOf(
            this.collateral.address,
            this.market2,
            this.outcome2,
            customer1
          )
        )
          .sub(
            TOTAL_COLLATERAL2.mul(toBN("90"))
              .div(toBN("100"))
              .div(NUMBER_CUSTOMERS2)
          )
          .abs()
          .should.be.bignumber.below(toBN("2"));
        (
          await this.conditionalTokens.collateralBalanceOf(
            this.collateral.address,
            this.market2,
            this.outcome2,
            customer2
          )
        )
          .sub(
            TOTAL_COLLATERAL2.mul(toBN("10"))
              .div(toBN("100"))
              .div(NUMBER_CUSTOMERS2)
          )
          .abs()
          .should.be.bignumber.below(toBN("2"));
        // TODO
      });

      // TODO: Unregistered customer receives zero.
      // TODO: Send money to registered and unregistered customers.
      // TODO: reportNumerator() called second time for the same customer.
    });
  });
});
