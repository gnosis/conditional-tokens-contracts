const ethSigUtil = require("eth-sig-util");

const { expectEvent, expectRevert } = require("openzeppelin-test-helpers");
const { toBN, randomHex } = web3.utils;
const {
  getConditionId,
  getCollectionId,
  combineCollectionIds,
  getPositionId
} = require("../utils/id-helpers")(web3.utils);

const ConditionalTokens = artifacts.require("ConditionalTokens");
const ERC20Mintable = artifacts.require("MockCoin");
const Forwarder = artifacts.require("Forwarder");
const DefaultCallbackHandler = artifacts.require("DefaultCallbackHandler.sol");
const GnosisSafe = artifacts.require("GnosisSafe");

const NULL_BYTES32 = `0x${"0".repeat(64)}`;

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
    it("should not be able to prepare a condition with no outcome slots", async function() {
      const questionId = randomHex(32);
      const outcomeSlotCount = 0;

      await expectRevert(
        this.conditionalTokens.prepareCondition(
          oracle,
          questionId,
          outcomeSlotCount
        ),
        "there should be more than one outcome slot"
      );
    });

    it("should not be able to prepare a condition with just one outcome slots", async function() {
      const questionId = randomHex(32);
      const outcomeSlotCount = 1;

      await expectRevert(
        this.conditionalTokens.prepareCondition(
          oracle,
          questionId,
          outcomeSlotCount
        ),
        "there should be more than one outcome slot"
      );
    });

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

      it("should make outcome slot count available via getOutcomeSlotCount", async function() {
        (
          await this.conditionalTokens.getOutcomeSlotCount(conditionId)
        ).should.be.bignumber.equal(outcomeSlotCount);
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

  describe("splitting and merging", function() {
    function shouldSplitAndMergePositions(trader) {
      const questionId = randomHex(32);
      const outcomeSlotCount = toBN(2);

      const conditionId = getConditionId(oracle, questionId, outcomeSlotCount);

      const collateralTokenCount = toBN(1e19);
      const splitAmount = toBN(4e18);
      const mergeAmount = toBN(3e18);

      function shouldWorkWithSplittingAndMerging({
        prepareTokens,
        doSplit,
        doMerge,
        doRedeem,
        collateralBalanceOf,
        getPositionForCollection,
        getExpectedEventCollateralProperties,
        deeperTests
      }) {
        beforeEach(prepareTokens);

        it("should not split on unprepared conditions", async function() {
          await doSplit.call(
            this,
            conditionId,
            [0b01, 0b10],
            splitAmount
          ).should.be.rejected;
        });

        context("with a condition prepared", async function() {
          beforeEach(async function() {
            await this.conditionalTokens.prepareCondition(
              oracle,
              questionId,
              outcomeSlotCount
            );
          });

          it("should not split if given index sets aren't disjoint", async function() {
            await doSplit.call(
              this,
              conditionId,
              [0b11, 0b10],
              splitAmount
            ).should.be.rejected;
          });

          it("should not split if partitioning more than condition's outcome slots", async function() {
            await doSplit.call(
              this,
              conditionId,
              [0b001, 0b010, 0b100],
              splitAmount
            ).should.be.rejected;
          });

          it("should not split if given a singleton partition", async function() {
            await doSplit.call(
              this,
              conditionId,
              [0b11],
              splitAmount
            ).should.be.rejected;
          });

          it("should not split if given an incomplete singleton partition", async function() {
            await doSplit.call(
              this,
              conditionId,
              [0b01],
              splitAmount
            ).should.be.rejected;
          });

          context("with valid split", function() {
            const partition = [0b01, 0b10];

            beforeEach(async function() {
              ({ tx: this.splitTx } = await doSplit.call(
                this,
                conditionId,
                partition,
                splitAmount
              ));
            });

            it("should emit a PositionSplit event", async function() {
              await expectEvent.inTransaction(
                this.splitTx,
                ConditionalTokens,
                "PositionSplit",
                Object.assign(
                  {
                    stakeholder: trader.address,
                    parentCollectionId: NULL_BYTES32,
                    conditionId,
                    // partition,
                    amount: splitAmount
                  },
                  getExpectedEventCollateralProperties.call(this)
                )
              );
            });

            it("should transfer split collateral from trader", async function() {
              (
                await collateralBalanceOf.call(this, trader.address)
              ).should.be.bignumber.equal(
                collateralTokenCount.sub(splitAmount)
              );
              (
                await collateralBalanceOf.call(
                  this,
                  this.conditionalTokens.address
                )
              ).should.be.bignumber.equal(splitAmount);
            });

            it("should mint amounts in positions associated with partition", async function() {
              for (const indexSet of partition) {
                const positionId = getPositionForCollection.call(
                  this,
                  getCollectionId(conditionId, indexSet)
                );

                (
                  await this.conditionalTokens.balanceOf(
                    trader.address,
                    positionId
                  )
                ).should.be.bignumber.equal(splitAmount);
              }
            });

            it("should not merge if amount exceeds balances in to-be-merged positions", async function() {
              await doMerge.call(
                this,
                conditionId,
                partition,
                splitAmount.addn(1)
              ).should.be.rejected;
            });

            context("with valid merge", function() {
              beforeEach(async function() {
                ({ tx: this.mergeTx } = await doMerge.call(
                  this,
                  conditionId,
                  partition,
                  mergeAmount
                ));
              });

              it("should emit a PositionsMerge event", async function() {
                await expectEvent.inTransaction(
                  this.mergeTx,
                  ConditionalTokens,
                  "PositionsMerge",
                  Object.assign(
                    {
                      stakeholder: trader.address,
                      parentCollectionId: NULL_BYTES32,
                      conditionId,
                      // partition,
                      amount: mergeAmount
                    },
                    getExpectedEventCollateralProperties.call(this)
                  )
                );
              });

              it("should transfer split collateral back to trader", async function() {
                (
                  await collateralBalanceOf.call(this, trader.address)
                ).should.be.bignumber.equal(
                  collateralTokenCount.sub(splitAmount).add(mergeAmount)
                );
                (
                  await collateralBalanceOf.call(
                    this,
                    this.conditionalTokens.address
                  )
                ).should.be.bignumber.equal(splitAmount.sub(mergeAmount));
              });

              it("should burn amounts in positions associated with partition", async function() {
                for (const indexSet of partition) {
                  const positionId = getPositionForCollection.call(
                    this,
                    getCollectionId(conditionId, indexSet)
                  );

                  (
                    await this.conditionalTokens.balanceOf(
                      trader.address,
                      positionId
                    )
                  ).should.be.bignumber.equal(splitAmount.sub(mergeAmount));
                }
              });
            });

            describe("transferring, reporting, and redeeming", function() {
              const transferAmount = toBN(1e18);
              const payoutNumerators = [toBN(3), toBN(7)];

              it("should not allow transferring more than split balance", async function() {
                const positionId = getPositionForCollection.call(
                  this,
                  getCollectionId(conditionId, partition[0])
                );

                await trader.execCall(
                  this.conditionalTokens,
                  "safeTransferFrom",
                  trader.address,
                  counterparty,
                  positionId,
                  splitAmount.addn(1),
                  "0x"
                ).should.be.rejected;
              });

              it("should not allow reporting by incorrect oracle", async function() {
                await expectRevert(
                  this.conditionalTokens.reportPayouts(
                    questionId,
                    payoutNumerators,
                    { from: notOracle }
                  ),
                  "condition not prepared or found"
                );
              });

              it("should not allow report with wrong questionId", async function() {
                const wrongQuestionId = randomHex(32);
                await expectRevert(
                  this.conditionalTokens.reportPayouts(
                    wrongQuestionId,
                    payoutNumerators,
                    { from: oracle }
                  ),
                  "condition not prepared or found"
                );
              });

              it("should not allow report with no slots", async function() {
                await expectRevert(
                  this.conditionalTokens.reportPayouts(questionId, [], {
                    from: oracle
                  }),
                  "there should be more than one outcome slot"
                );
              });

              it("should not allow report with wrong number of slots", async function() {
                await expectRevert(
                  this.conditionalTokens.reportPayouts(questionId, [2, 3, 5], {
                    from: oracle
                  }),
                  "condition not prepared or found"
                );
              });

              it("should not allow report with zero payouts in all slots", async function() {
                await expectRevert(
                  this.conditionalTokens.reportPayouts(questionId, [0, 0], {
                    from: oracle
                  }),
                  "payout is all zeroes"
                );
              });

              context("with valid transfer and oracle report", function() {
                beforeEach(async function() {
                  const positionId = getPositionForCollection.call(
                    this,
                    getCollectionId(conditionId, partition[0])
                  );

                  ({ tx: this.transferTx } = await trader.execCall(
                    this.conditionalTokens,
                    "safeTransferFrom",
                    trader.address,
                    counterparty,
                    positionId,
                    transferAmount,
                    "0x"
                  ));
                  ({
                    logs: this.reportLogs
                  } = await this.conditionalTokens.reportPayouts(
                    questionId,
                    payoutNumerators,
                    { from: oracle }
                  ));
                });

                it("should not merge if any amount is short", async function() {
                  await doMerge.call(
                    this,
                    conditionId,
                    partition,
                    splitAmount
                  ).should.be.rejected;
                });

                it("should emit ConditionResolution event", async function() {
                  expectEvent.inLogs(this.reportLogs, "ConditionResolution", {
                    conditionId,
                    oracle,
                    questionId,
                    outcomeSlotCount
                  });
                });

                it("should make reported payout numerators available", async function() {
                  for (let i = 0; i < payoutNumerators.length; i++) {
                    (
                      await this.conditionalTokens.payoutNumerators(
                        conditionId,
                        i
                      )
                    ).should.be.bignumber.equal(payoutNumerators[i]);
                  }
                });

                describe("redeeming", function() {
                  const payoutDenominator = payoutNumerators.reduce(
                    (a, b) => a.add(b),
                    toBN(0)
                  );
                  const payout = [
                    splitAmount.sub(transferAmount),
                    splitAmount
                  ].reduce(
                    (acc, amount, i) =>
                      acc.add(
                        amount.mul(payoutNumerators[i]).div(payoutDenominator)
                      ),
                    toBN(0)
                  );

                  beforeEach(async function() {
                    ({ tx: this.redeemTx } = await doRedeem.call(
                      this,
                      conditionId,
                      partition
                    ));
                  });

                  it("should emit PayoutRedemption event", async function() {
                    await expectEvent.inTransaction(
                      this.redeemTx,
                      ConditionalTokens,
                      "PayoutRedemption",
                      Object.assign(
                        {
                          redeemer: trader.address,
                          parentCollectionId: NULL_BYTES32,
                          conditionId,
                          // indexSets: partition,
                          payout
                        },
                        getExpectedEventCollateralProperties.call(this)
                      )
                    );
                  });

                  it("should zero out redeemed positions", async function() {
                    for (const indexSet of partition) {
                      const positionId = getPositionForCollection.call(
                        this,
                        getCollectionId(conditionId, indexSet)
                      );
                      (
                        await this.conditionalTokens.balanceOf(
                          trader.address,
                          positionId
                        )
                      ).should.be.bignumber.equal("0");
                    }
                  });

                  it("should not affect other's positions", async function() {
                    const positionId = getPositionForCollection.call(
                      this,
                      getCollectionId(conditionId, partition[0])
                    );
                    (
                      await this.conditionalTokens.balanceOf(
                        counterparty,
                        positionId
                      )
                    ).should.be.bignumber.equal(transferAmount);
                  });

                  it("should credit payout as collateral", async function() {
                    (
                      await collateralBalanceOf.call(this, trader.address)
                    ).should.be.bignumber.equal(
                      collateralTokenCount.sub(splitAmount).add(payout)
                    );
                  });
                });
              });
            });
          });
        });

        if (deeperTests)
          context("with many conditions prepared", async function() {
            const conditions = Array.from({ length: 3 }, () => ({
              oracle,
              questionId: randomHex(32),
              outcomeSlotCount: toBN(4)
            }));

            conditions.forEach(condition => {
              condition.id = getConditionId(
                condition.oracle,
                condition.questionId,
                condition.outcomeSlotCount
              );
            });

            beforeEach(async function() {
              for (const {
                oracle,
                questionId,
                outcomeSlotCount
              } of conditions) {
                await this.conditionalTokens.prepareCondition(
                  oracle,
                  questionId,
                  outcomeSlotCount
                );
              }
            });

            context("when trader has collateralized a condition", function() {
              const condition = conditions[0];
              const { oracle, questionId, outcomeSlotCount } = condition;
              const conditionId = condition.id;
              const finalReport = [0, 33, 289, 678].map(toBN);
              const payoutDenominator = finalReport.reduce((a, b) => a.add(b));
              const partition = [0b0111, 0b1000];
              const positionIndexSet = partition[0];

              beforeEach(async function() {
                await doSplit.call(
                  this,
                  conditionId,
                  partition,
                  collateralTokenCount
                );
                await trader.execCall(
                  this.conditionalTokens,
                  "safeTransferFrom",
                  trader.address,
                  counterparty,
                  getPositionForCollection.call(
                    this,
                    getCollectionId(conditionId, partition[1])
                  ),
                  collateralTokenCount,
                  "0x"
                );
              });

              context(
                "when trader splits to a deeper position with another condition",
                function() {
                  const conditionId2 = conditions[1].id;
                  const partition2 = [0b0001, 0b0010, 0b1100];
                  const deepSplitAmount = toBN(4e18);
                  const parentCollectionId = getCollectionId(
                    conditionId,
                    positionIndexSet
                  );

                  beforeEach(async function() {
                    ({ tx: this.deepSplitTx } = await doSplit.call(
                      this,
                      conditionId2,
                      partition2,
                      deepSplitAmount,
                      parentCollectionId
                    ));
                  });

                  it("combines collection IDs", async function() {
                    for (const indexSet of partition2) {
                      (
                        await this.conditionalTokens.getCollectionId(
                          parentCollectionId,
                          conditionId2,
                          indexSet
                        )
                      ).should.be.equal(
                        combineCollectionIds([
                          parentCollectionId,
                          getCollectionId(conditionId2, indexSet)
                        ])
                      );
                    }
                  });

                  it("emits PositionSplit event", async function() {
                    await expectEvent.inTransaction(
                      this.deepSplitTx,
                      ConditionalTokens,
                      "PositionSplit",
                      Object.assign(
                        {
                          stakeholder: trader.address,
                          parentCollectionId,
                          conditionId: conditionId2,
                          // partition: partition2,
                          amount: deepSplitAmount
                        },
                        getExpectedEventCollateralProperties.call(this)
                      )
                    );
                  });

                  it("burns value in the parent position", async function() {
                    (
                      await this.conditionalTokens.balanceOf(
                        trader.address,
                        getPositionForCollection.call(this, parentCollectionId)
                      )
                    ).should.be.bignumber.equal(
                      collateralTokenCount.sub(deepSplitAmount)
                    );
                  });

                  it("mints values in the child positions", async function() {
                    for (const indexSet of partition2) {
                      const positionId = getPositionForCollection.call(
                        this,
                        combineCollectionIds([
                          parentCollectionId,
                          getCollectionId(conditionId2, indexSet)
                        ])
                      );

                      (
                        await this.conditionalTokens.balanceOf(
                          trader.address,
                          positionId
                        )
                      ).should.be.bignumber.equal(deepSplitAmount);
                    }
                  });
                }
              );

              context("with valid report", function() {
                beforeEach(async function() {
                  ({
                    logs: this.reportLogs
                  } = await this.conditionalTokens.reportPayouts(
                    questionId,
                    finalReport,
                    { from: oracle }
                  ));
                });

                it("should emit ConditionResolution event", function() {
                  expectEvent.inLogs(this.reportLogs, "ConditionResolution", {
                    conditionId,
                    oracle,
                    questionId,
                    outcomeSlotCount
                  });
                });

                it("should reflect report via payoutNumerators", async function() {
                  for (let i = 0; i < finalReport.length; i++) {
                    (
                      await this.conditionalTokens.payoutNumerators(
                        conditionId,
                        i
                      )
                    ).should.be.bignumber.equal(finalReport[i]);
                  }
                });

                it("should not allow an update to the report", async function() {
                  const badUpdateReport = finalReport.map((x, i) =>
                    i === 1 ? x : toBN(0)
                  );
                  await expectRevert(
                    this.conditionalTokens.reportPayouts(
                      questionId,
                      badUpdateReport,
                      { from: oracle }
                    ),
                    "payout denominator already set"
                  );
                });

                context("with valid redemption", async function() {
                  const payout = collateralTokenCount
                    .mul(
                      finalReport.reduce(
                        (acc, term, i) =>
                          positionIndexSet & (1 << i) ? acc.add(term) : acc,
                        toBN(0)
                      )
                    )
                    .div(payoutDenominator);

                  beforeEach(async function() {
                    ({ tx: this.redeemTx } = await doRedeem.call(
                      this,
                      conditionId,
                      [positionIndexSet]
                    ));
                  });

                  it("should emit PayoutRedemption event", async function() {
                    await expectEvent.inTransaction(
                      this.redeemTx,
                      ConditionalTokens,
                      "PayoutRedemption",
                      Object.assign(
                        {
                          redeemer: trader.address,
                          parentCollectionId: NULL_BYTES32,
                          conditionId,
                          // indexSets: partition,
                          payout
                        },
                        getExpectedEventCollateralProperties.call(this)
                      )
                    );
                  });
                });
              });
            });
          });
      }

      context("with an ERC-20 collateral allowance", function() {
        shouldWorkWithSplittingAndMerging({
          async prepareTokens() {
            this.collateralToken = await ERC20Mintable.new({ from: minter });
            await this.collateralToken.mint(
              trader.address,
              collateralTokenCount,
              { from: minter }
            );
            await trader.execCall(
              this.collateralToken,
              "approve",
              this.conditionalTokens.address,
              collateralTokenCount
            );
          },
          async doSplit(conditionId, partition, amount, parentCollectionId) {
            return await trader.execCall(
              this.conditionalTokens,
              "splitPosition",
              this.collateralToken.address,
              parentCollectionId || NULL_BYTES32,
              conditionId,
              partition,
              amount
            );
          },
          async doMerge(conditionId, partition, amount, parentCollectionId) {
            return await trader.execCall(
              this.conditionalTokens,
              "mergePositions",
              this.collateralToken.address,
              parentCollectionId || NULL_BYTES32,
              conditionId,
              partition,
              amount
            );
          },
          async doRedeem(conditionId, indexSets, parentCollectionId) {
            return await trader.execCall(
              this.conditionalTokens,
              "redeemPositions",
              this.collateralToken.address,
              parentCollectionId || NULL_BYTES32,
              conditionId,
              indexSets
            );
          },
          async collateralBalanceOf(address) {
            return await this.collateralToken.balanceOf(address);
          },
          getPositionForCollection(collectionId) {
            return getPositionId(this.collateralToken.address, collectionId);
          },
          getExpectedEventCollateralProperties() {
            return { collateralToken: this.collateralToken.address };
          },
          deeperTests: true
        });
      });
    }

    context("with an EOA", function() {
      shouldSplitAndMergePositions({
        address: eoaTrader,
        async execCall(contract, method, ...args) {
          return await contract[method](...args, { from: eoaTrader });
        }
      });
    });

    context.skip("with a Forwarder", function() {
      let trader = {};
      before(async function() {
        const forwarder = await Forwarder.new();
        async function forwardCall(contract, method, ...args) {
          // ???: why is reformatting the args necessary here?
          args = args.map(arg =>
            Array.isArray(arg) ? arg.map(a => a.toString()) : arg.toString()
          );

          return await forwarder.call(
            contract.address,
            contract.contract.methods[method](...args).encodeABI(),
            { from: fwdExecutor }
          );
        }

        trader.address = forwarder.address;
        trader.execCall = forwardCall;
      });

      shouldSplitAndMergePositions(trader);
    });

    context.skip("with a Gnosis Safe", function() {
      let trader = {};
      before(async function() {
        const zeroAccount = `0x${"0".repeat(40)}`;
        const safeOwners = Array.from({ length: 2 }, () =>
          web3.eth.accounts.create()
        );
        safeOwners.sort(({ address: a }, { address: b }) =>
          a.toLowerCase() < b.toLowerCase() ? -1 : a === b ? 0 : 1
        );
        const callbackHandler = await DefaultCallbackHandler.new();
        const gnosisSafe = await GnosisSafe.new();
        await gnosisSafe.setup(
          safeOwners.map(({ address }) => address),
          safeOwners.length,
          zeroAccount,
          "0x",
          callbackHandler.address,
          zeroAccount,
          0,
          zeroAccount
        );
        const gnosisSafeTypedDataCommon = {
          types: {
            EIP712Domain: [{ name: "verifyingContract", type: "address" }],
            SafeTx: [
              { name: "to", type: "address" },
              { name: "value", type: "uint256" },
              { name: "data", type: "bytes" },
              { name: "operation", type: "uint8" },
              { name: "safeTxGas", type: "uint256" },
              { name: "baseGas", type: "uint256" },
              { name: "gasPrice", type: "uint256" },
              { name: "gasToken", type: "address" },
              { name: "refundReceiver", type: "address" },
              { name: "nonce", type: "uint256" }
            ],
            SafeMessage: [{ name: "message", type: "bytes" }]
          },
          domain: {
            verifyingContract: gnosisSafe.address
          }
        };

        async function gnosisSafeCall(contract, method, ...args) {
          const safeOperations = {
            CALL: 0,
            DELEGATECALL: 1,
            CREATE: 2
          };
          const nonce = await gnosisSafe.nonce();

          // ???: why is reformatting the args necessary here?
          args = args.map(arg =>
            Array.isArray(arg) ? arg.map(a => a.toString()) : arg.toString()
          );

          const txData = contract.contract.methods[method](...args).encodeABI();
          const signatures = safeOwners.map(safeOwner =>
            ethSigUtil.signTypedData(
              Buffer.from(safeOwner.privateKey.replace("0x", ""), "hex"),
              {
                data: Object.assign(
                  {
                    primaryType: "SafeTx",
                    message: {
                      to: contract.address,
                      value: 0,
                      data: txData,
                      operation: safeOperations.CALL,
                      safeTxGas: 0,
                      baseGas: 0,
                      gasPrice: 0,
                      gasToken: zeroAccount,
                      refundReceiver: zeroAccount,
                      nonce
                    }
                  },
                  gnosisSafeTypedDataCommon
                )
              }
            )
          );
          const tx = await gnosisSafe.execTransaction(
            contract.address,
            0,
            txData,
            safeOperations.CALL,
            0,
            0,
            0,
            zeroAccount,
            zeroAccount,
            `0x${signatures.map(s => s.replace("0x", "")).join("")}`,
            { from: safeExecutor }
          );
          if (tx.logs[0] && tx.logs[0].event === "ExecutionFailed")
            throw new Error(`Safe transaction ${method}(${args}) failed`);
          return tx;
        }

        trader.address = gnosisSafe.address;
        trader.execCall = gnosisSafeCall;
      });

      shouldSplitAndMergePositions(trader);
    });
  });
});
