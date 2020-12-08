"strict";

const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN } = web3.utils;
const {
  INITIAL_CUSTOMER_BALANCE,
  conditionalTokenId,
  collateralRedeemedTokenId
} = require("../utils/manyid-helpers")(web3.utils);

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
        this.marketId1 = this.logs1[0].args.marketId;
        ({ logs: this.logs2 } = await this.conditionalTokens.createMarket());
        this.marketId2 = this.logs2[0].args.marketId;
        ({ logs: this.logs3 } = await this.conditionalTokens.createOracle());
        this.oracleId1 = this.logs3[0].args.oracleId;
        ({ logs: this.logs4 } = await this.conditionalTokens.createOracle());
        this.oracleId2 = this.logs4[0].args.oracleId;
      });

      it("should emit a MarketCreated event", function() {
        this.marketId1.should.be.bignumber.equal("0");
        this.marketId2.should.be.bignumber.equal("1");
        expectEvent.inLogs(this.logs1, "MarketCreated", {
          oracleOwner: oracle1,
          marketId: this.marketId1
        });
        expectEvent.inLogs(this.logs2, "MarketCreated", {
          oracleOwner: oracle1,
          marketId: this.marketId2
        });
        // TODO: Check "OracleCreated"
      });

      it("should leave payout denominator unset", async function() {
        (
          await this.conditionalTokens.payoutDenominator(this.marketId1)
        ).should.be.bignumber.equal("0");
        (
          await this.conditionalTokens.payoutDenominator(this.marketId2)
        ).should.be.bignumber.equal("0");
      });

      it("should not be able to register the same customer more than once for the same marketId", async function() {
        await this.conditionalTokens.registerCustomer(
          this.marketId1,
          customer1,
          [],
          {
            from: customer1
          }
        );
        await expectRevert(
          this.conditionalTokens.registerCustomer(
            this.marketId1,
            customer1,
            [],
            {
              from: customer1
            }
          ),
          "customer already registered"
        );
        // TODO: Check that can register the same customer for different marketIds.
      });

      it("checking the math", async function() {
        const customers = [customer1, customer2];
        const oracleIdsInfo = [
          {
            oracleId: this.oracleId1,
            numerators: [{ numerator: toBN("45") }, { numerator: toBN("60") }]
          },
          {
            oracleId: this.oracleId2,
            numerators: [{ numerator: toBN("33") }, { numerator: toBN("90") }]
          }
        ];
        const marketIds = [this.marketId1, this.marketId2];
        // TODO: Simplify customers array. // TODO: Should be grouped by marketIds.
        const products = [
          {
            marketId: this.marketId1,
            oracleId: 0,
            donors: [
              { account: donor1, amount: toBN("10000000000") },
              { account: donor2, amount: toBN("1000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("20000000000") },
              { account: staker2, amount: toBN("2000000000000") }
            ],
            customers: [{ account: 0 }, { account: 1 }]
          },
          {
            marketId: this.marketId1,
            oracleId: 1,
            donors: [
              { account: donor1, amount: toBN("20000000000") },
              { account: donor2, amount: toBN("2000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("30000000000") },
              { account: staker2, amount: toBN("4000000000000") }
            ],
            customers: [{ account: 0 }, { account: 1 }]
          },
          {
            marketId: this.marketId2,
            oracleId: 0,
            donors: [
              { account: donor1, amount: toBN("50000000000") },
              { account: donor2, amount: toBN("5000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("60000000000") },
              { account: staker2, amount: toBN("6000000000000") }
            ],
            customers: [{ account: 0 }, { account: 1 }]
          },
          {
            marketId: this.marketId2,
            oracleId: 1,
            donors: [
              { account: donor1, amount: toBN("70000000000") },
              { account: donor2, amount: toBN("7000000000000") }
            ],
            stakers: [
              { account: staker1, amount: toBN("80000000000") },
              { account: staker2, amount: toBN("9000000000000") }
            ],
            customers: [{ account: 0 }, { account: 1 }]
          }
        ];

        async function setupOneProduct(product) {
          for (let donor of product.donors) {
            await this.collateral.approve(
              this.conditionalTokens.address,
              "1000000000000000" /* a big number */,
              { from: donor.account }
            );
            const oracleIdInfo = oracleIdsInfo[product.oracleId];
            await this.conditionalTokens.donate(
              this.collateral.address,
              product.marketId,
              oracleIdInfo.oracleId,
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
            const oracleIdInfo = oracleIdsInfo[product.oracleId];
            await this.conditionalTokens.stakeCollateral(
              this.collateral.address,
              product.marketId,
              oracleIdInfo.oracleId,
              staker.amount,
              [],
              { from: staker.account }
            );
          }

          // To complicate the task of the test, we will transfer some tokens from the first customer to the rest.
          async function transferSomeConditional(amount) {
            for (let i = 1; i != customers.length; ++i) {
              await this.conditionalTokens.safeTransferFrom(
                customers[0],
                customers[i],
                conditionalTokenId(product.marketId, customers[0]),
                amount,
                [],
                { from: customers[0] }
              );
            }
          }

          await transferSomeConditional.bind(this)(web3.utils.toWei("2.3"));

          const oracleIdInfo = oracleIdsInfo[product.oracleId];
          for (let i in oracleIdInfo.numerators) {
            await this.conditionalTokens.reportNumerator(
              oracleIdInfo.oracleId,
              customers[i],
              oracleIdInfo.numerators[i].numerator
            );
          }
          await this.conditionalTokens.finishOracle(oracleIdInfo.oracleId);

          await transferSomeConditional.bind(this)(web3.utils.toWei("1.2"));
        }

        async function redeemOneProduct(product) {
          const oracleIdInfo = oracleIdsInfo[product.oracleId];
          let totalCollateral = toBN("0");
          for (let donor of product.donors) {
            totalCollateral = totalCollateral.add(donor.amount);
          }
          for (let staker of product.stakers) {
            totalCollateral = totalCollateral.add(staker.amount);
          }
          let denominator = toBN("0");
          for (let n of oracleIdInfo.numerators) {
            denominator = denominator.add(n.numerator);
          }
          (
            await this.conditionalTokens.payoutDenominator(
              oracleIdInfo.oracleId
            )
          ).should.be.bignumber.equal(denominator);
          for (let customer of product.customers) {
            const oracleIdInfo = oracleIdsInfo[product.oracleId];
            const account = customers[customer.account];
            const initialCollateralBalance = await this.conditionalTokens.initialCollateralBalanceOf(
              this.collateral.address,
              product.marketId,
              oracleIdInfo.oracleId,
              account,
              account
            );
            initialCollateralBalance
              .sub(
                totalCollateral
                  .mul(oracleIdInfo.numerators[customer.account].numerator)
                  .mul(
                    await this.conditionalTokens.balanceOf(
                      account,
                      conditionalTokenId(product.marketId, account)
                    )
                  )
                  .div(denominator)
                  .div(INITIAL_CUSTOMER_BALANCE)
              )
              .abs()
              .should.be.bignumber.below(toBN("2"));

            // Two calls should be like one.
            // TODO: Redeem somebody other's token.
            await this.conditionalTokens.activateRedeem(
              this.collateral.address,
              product.marketId,
              oracleIdInfo.oracleId,
              account,
              [],
              { from: account }
            );
            await expectRevert(
              this.conditionalTokens.activateRedeem(
                this.collateral.address,
                product.marketId,
                oracleIdInfo.oracleId,
                account,
                [],
                { from: account }
              ),
              "Already redeemed."
            );

            // Now will withdraw half twice.
            const halfBalance = initialCollateralBalance.div(toBN("2"));

            {
              const oldBalance = await this.collateral.balanceOf(account);
              await this.conditionalTokens.withdrawCollateral(
                this.collateral.address,
                product.marketId,
                oracleIdInfo.oracleId,
                account,
                halfBalance,
                { from: account }
              );

              const newBalance = await this.collateral.balanceOf(account);
              newBalance.sub(oldBalance).should.be.bignumber.equal(halfBalance);
            }

            {
              const oldBalance = await this.collateral.balanceOf(account);
              await this.conditionalTokens.withdrawCollateral(
                this.collateral.address,
                product.marketId,
                oracleIdInfo.oracleId,
                account,
                halfBalance,
                { from: account }
              );

              const newBalance = await this.collateral.balanceOf(account);
              newBalance.sub(oldBalance).should.be.bignumber.equal(halfBalance);
            }

            const remainingCollateralBalance = await this.conditionalTokens.balanceOf(
              account,
              collateralRedeemedTokenId(
                this.collateral.address,
                product.marketId,
                oracleIdInfo.oracleId
              )
            );
            remainingCollateralBalance.should.be.bignumber.below("2");

            await expectRevert(
              this.conditionalTokens.withdrawCollateral(
                this.collateral.address,
                product.marketId,
                oracleIdInfo.oracleId,
                account,
                halfBalance,
                { from: account }
              ),
              "SafeMath: subtraction overflow"
            );

            // TODO: Also check withdrawal to a third-party account.
          }
        }

        for (let customer of customers) {
          for (let marketId of marketIds) {
            await this.conditionalTokens.registerCustomer(
              marketId,
              customer,
              [],
              {
                from: customer
              }
            );
          }
        }

        // Can be written shorter:
        // Promise.all(products.map(testOneProduct.bind(this)));
        // But let us be on reliability side:
        for (let product of products) {
          await setupOneProduct.bind(this)(product);
        }
        for (let product of products) {
          await redeemOneProduct.bind(this)(product);
        }

        // TODO
      });

      // TODO: Unregistered customer receives zero.
      // TODO: Send money to registered and unregistered customers.
      // TODO: reportNumerator() called second time for the same customer.
      // TODO: Test all functions and all variants.
    });
  });
});
