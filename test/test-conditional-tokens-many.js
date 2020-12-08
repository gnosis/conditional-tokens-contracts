const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN } = web3.utils;

const ConditionalTokensMany = artifacts.require("ConditionalTokensMany");
const ERC20Mintable = artifacts.require("MockCoin");

contract("ConditionalTokensMany", function(accounts) {
  const [
    oracle1,
    customer1,
    customer2,
    donor1,
    donor2,
    staker1,
    staker2
  ] = accounts;

  beforeEach("initiate token contracts", async function() {
    this.conditionalTokens = await ConditionalTokensMany.new();
    this.collateral = await ERC20Mintable.new(); // TODO: Check multiple collaterals
    this.collateral.mint(donor1, "1000000000000000000000");
    this.collateral.mint(donor2, "1000000000000000000000");
    this.collateral.mint(staker1, "1000000000000000000000");
    this.collateral.mint(staker2, "1000000000000000000000");
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
        await this.conditionalTokens.registerCustomer(
          this.market1,
          customer1,
          [],
          {
            from: customer1
          }
        );
        await expectRevert(
          this.conditionalTokens.registerCustomer(this.market1, customer1, [], {
            from: customer1
          }),
          "customer already registered"
        );
        // TODO: Check that can register the same customer for different markets.
      });

      it("checking the math", async function() {
        const outcomesInfo = [
          {
            outcome: this.outcome1,
            numerators: [
              { account: customer1, numerator: toBN("45") },
              { account: customer2, numerator: toBN("60") }
            ]
          },
          {
            outcome: this.outcome2,
            numerators: [
              { account: customer1, numerator: toBN("33") },
              { account: customer2, numerator: toBN("90") }
            ]
          }
        ];
        const products = [
          {
            market: this.market1,
            outcome: 0,
            donors: [
              { account: donor1, amount: toBN("10000000000") },
              { account: donor2, amount: toBN("1000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("20000000000") },
              { account: staker2, amount: toBN("2000000000000") }
            ],
            customers: [
              { account: customer1, numerator: toBN("3") },
              { account: customer2, numerator: toBN("2") }
            ]
          },
          {
            market: this.market1,
            outcome: 1,
            donors: [
              { account: donor1, amount: toBN("20000000000") },
              { account: donor2, amount: toBN("2000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("30000000000") },
              { account: staker2, amount: toBN("4000000000000") }
            ],
            customers: [
              { account: customer1, numerator: toBN("90") },
              { account: customer2, numerator: toBN("10") }
            ]
          },
          {
            market: this.market2,
            outcome: 0,
            donors: [
              { account: donor1, amount: toBN("50000000000") },
              { account: donor2, amount: toBN("5000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("60000000000") },
              { account: staker2, amount: toBN("6000000000000") }
            ],
            customers: [
              { account: customer1, numerator: toBN("5") },
              { account: customer2, numerator: toBN("4") }
            ]
          },
          {
            market: this.market2,
            outcome: 1,
            donors: [
              { account: donor1, amount: toBN("70000000000") },
              { account: donor2, amount: toBN("7000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("80000000000") },
              { account: staker2, amount: toBN("9000000000000") }
            ],
            customers: [
              { account: customer1, numerator: toBN("80") },
              { account: customer2, numerator: toBN("20") }
            ]
          }
        ];

        async function testOneProduct(product) {
          for (let customerInfo of product.customers) {
            await this.conditionalTokens.registerCustomer(
              product.market,
              customerInfo.account,
              [],
              {
                from: customerInfo.account
              }
            );
          }
          for (let donor of product.donors) {
            await this.collateral.approve(
              this.conditionalTokens.address,
              "1000000000000000" /* a big number */,
              { from: donor.account }
            );
            const outcomeInfo = outcomesInfo[product.outcome];
            await this.conditionalTokens.donate(
              this.collateral.address,
              product.market,
              outcomeInfo.outcome,
              donor.amount,
              [],
              { from: donor.account }
            );
          }
          for (let staker of product.stakers) {
            await this.collateral.approve(
              this.conditionalTokens.address,
              "1000000000000000" /* a big number */,
              { from: staker.account }
            );
            const outcomeInfo = outcomesInfo[product.outcome];
            await this.conditionalTokens.stakeCollateral(
              this.collateral.address,
              product.market,
              outcomeInfo.outcome,
              staker.amount,
              [],
              { from: staker.account }
            );
          }

          const outcomeInfo = outcomesInfo[product.outcome];
          for (let numeratorInfo of outcomeInfo.numerators) {
            await this.conditionalTokens.reportNumerator(
              outcomeInfo.outcome,
              numeratorInfo.account,
              numeratorInfo.numerator
            );
          }
          await this.conditionalTokens.finishOutcome(outcomeInfo.outcome);

          let totalCollateral = toBN("0");
          for (let donor of product.donors) {
            totalCollateral = totalCollateral.add(donor.amount);
          }
          for (let staker of product.stakers) {
            totalCollateral = totalCollateral.add(staker.amount);
          }
          let denominator = toBN("0");
          for (let customer of product.customers) {
            denominator = denominator.add(customer.numerator);
          }
          for (let customer of product.customers) {
            const outcomeInfo = outcomesInfo[product.outcome];
            console.log([
              (
                await this.conditionalTokens.collateralBalanceOf(
                  this.collateral.address,
                  product.market,
                  outcomeInfo.outcome,
                  customer.account
                )
              ).toString(),
              totalCollateral
                .mul(customer.numerator)
                .div(denominator)
                .div(toBN(product.customers.length))
                .toString()
            ]);
            (
              await this.conditionalTokens.collateralBalanceOf(
                this.collateral.address,
                product.market,
                outcomeInfo.outcome,
                customer.account
              )
            )
              .sub(
                totalCollateral
                  .mul(customer.numerator)
                  .div(denominator)
                  .div(toBN(product.customers.length))
              )
              .abs()
              .should.be.bignumber.below(toBN("2"));
          }
        }

        // Promise.all(products.forEach(testOneProduct.bind(this)));
        for (let product of products) {
          await testOneProduct.bind(this)(product);
        }

        // TODO
      });

      // TODO: Unregistered customer receives zero.
      // TODO: Send money to registered and unregistered customers.
      // TODO: reportNumerator() called second time for the same customer.
    });
  });
});
