const ethSigUtil = require("eth-sig-util");

const { assertRejects, getParamFromTxEvent } = require("./utils");
const { padLeft, asciiToHex, toBN, fromWei, soliditySha3 } = web3.utils;

const ConditionalTokens = artifacts.require("ConditionalTokens");
const ERC20Mintable = artifacts.require("MockCoin");
const Forwarder = artifacts.require("Forwarder");
const GnosisSafe = artifacts.require("GnosisSafe");

function getConditionId(oracle, questionId, outcomeSlotCount) {
  return soliditySha3(
    { t: "address", v: oracle },
    { t: "bytes32", v: questionId },
    { t: "uint", v: outcomeSlotCount }
  );
}

function getCollectionId(conditionId, indexSet) {
  return soliditySha3(
    { t: "bytes32", v: conditionId },
    { t: "uint", v: indexSet }
  );
}

function combineCollectionIds(collectionIds) {
  return (
    "0x" +
    collectionIds
      .reduce((acc, collectionId) => acc.add(toBN(collectionId)), toBN(0))
      .maskn(256)
      .toString(16, 64)
  );
}

function getPositionId(collateralToken, collectionId) {
  return soliditySha3(
    { t: "address", v: collateralToken },
    { t: "bytes32", v: collectionId }
  );
}

contract("ConditionalTokens", function(accounts) {
  let collateralToken;
  const minter = accounts[0];
  let oracle, questionId, outcomeSlotCount, conditionalTokens;
  let conditionId;

  before(async () => {
    conditionalTokens = await ConditionalTokens.deployed();
    collateralToken = await ERC20Mintable.new({ from: minter });

    // prepare condition
    oracle = accounts[1];

    questionId =
      "0xcafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe";
    outcomeSlotCount = 2;
    await conditionalTokens.prepareCondition(
      oracle,
      questionId,
      outcomeSlotCount
    );

    conditionId = getConditionId(oracle, questionId, outcomeSlotCount);
  });

  it("should not be able to prepare a condition with no outcome slots", async () => {
    await assertRejects(
      conditionalTokens.prepareCondition(oracle, questionId, 0),
      "Transaction should have reverted."
    );
  });

  it("should not be able to prepare a condition with just one outcome slots", async () => {
    await assertRejects(
      conditionalTokens.prepareCondition(oracle, questionId, 1),
      "Transaction should have reverted."
    );
  });

  it("should have obtainable conditionIds if in possession of oracle, questionId, and outcomeSlotCount", async () => {
    assert.equal(
      (await conditionalTokens.getOutcomeSlotCount(conditionId)).valueOf(),
      outcomeSlotCount
    );
    assert.equal(
      (await conditionalTokens.payoutDenominator(conditionId)).valueOf(),
      0
    );
  });

  it("should not be able to prepare the same condition more than once", async () => {
    await assertRejects(
      conditionalTokens.prepareCondition(oracle, questionId, outcomeSlotCount),
      "Transaction should have reverted."
    );
  });

  function shouldSplitAndMergePositionsOnOutcomeSlots(trader) {
    it("should split and merge positions on outcome slots", async () => {
      const collateralTokenCount = toBN(1e19);
      await collateralToken.mint(trader.address, collateralTokenCount, {
        from: minter
      });
      assert(
        collateralTokenCount.eq(
          await collateralToken.balanceOf.call(trader.address)
        )
      );

      await trader.execCall(
        collateralToken,
        "approve",
        conditionalTokens.address,
        collateralTokenCount
      );

      for (let i = 0; i < 10; i++) {
        await trader.execCall(
          conditionalTokens,
          "splitPosition",
          collateralToken.address,
          asciiToHex(0),
          conditionId,
          [0b01, 0b10],
          collateralTokenCount.divn(10)
        );
      }

      assert.equal(
        collateralTokenCount.toString(),
        (await collateralToken.balanceOf.call(
          conditionalTokens.address
        )).toString()
      );
      assert.equal(await collateralToken.balanceOf.call(trader.address), 0);

      assert(
        collateralTokenCount.eq(
          await conditionalTokens.balanceOf.call(
            trader.address,
            getPositionId(
              collateralToken.address,
              getCollectionId(conditionId, 0b01)
            )
          )
        )
      );
      assert(
        collateralTokenCount.eq(
          await conditionalTokens.balanceOf.call(
            trader.address,
            getPositionId(
              collateralToken.address,
              getCollectionId(conditionId, 0b10)
            )
          )
        )
      );

      // Validate getters
      assert.equal(
        await conditionalTokens.getOutcomeSlotCount.call(conditionId),
        2
      );

      await trader.execCall(
        conditionalTokens,
        "mergePositions",
        collateralToken.address,
        asciiToHex(0),
        conditionId,
        [0b01, 0b10],
        collateralTokenCount
      );
      assert(
        collateralTokenCount.eq(
          await collateralToken.balanceOf.call(trader.address)
        )
      );
      assert.equal(
        await collateralToken.balanceOf.call(conditionalTokens.address),
        0
      );

      assert.equal(
        await conditionalTokens.balanceOf.call(
          trader.address,
          getPositionId(
            collateralToken.address,
            getCollectionId(conditionId, 0b01)
          )
        ),
        0
      );
      assert.equal(
        await conditionalTokens.balanceOf.call(
          trader.address,
          getPositionId(
            collateralToken.address,
            getCollectionId(conditionId, 0b10)
          )
        ),
        0
      );
    });
  }

  context("with EOAs", () => {
    shouldSplitAndMergePositionsOnOutcomeSlots({
      address: accounts[0],
      async execCall(contract, method, ...args) {
        return await contract[method](...args, { from: accounts[0] });
      }
    });
  });

  context("with Forwarder", () => {
    let trader = {};
    before(async () => {
      const forwarder = await Forwarder.new();
      const executor = accounts[2];
      async function forwardCall(contract, method, ...args) {
        // ???: why is reformatting the args necessary here?
        args = args.map(arg =>
          Array.isArray(arg) ? arg.map(a => a.toString()) : arg.toString()
        );

        return await forwarder.call(
          contract.address,
          contract.contract.methods[method](...args).encodeABI(),
          { from: executor }
        );
      }

      trader.address = forwarder.address;
      trader.execCall = forwardCall;
    });

    shouldSplitAndMergePositionsOnOutcomeSlots(trader);
  });

  context("with Gnosis Safes", () => {
    let trader = {};
    before(async () => {
      const zeroAccount = `0x${"0".repeat(40)}`;
      const safeOwners = Array.from({ length: 2 }, () =>
        web3.eth.accounts.create()
      );
      safeOwners.sort(({ address: a }, { address: b }) =>
        a.toLowerCase() < b.toLowerCase() ? -1 : a === b ? 0 : 1
      );
      const gnosisSafe = await GnosisSafe.new();
      await gnosisSafe.setup(
        safeOwners.map(({ address }) => address),
        safeOwners.length,
        zeroAccount,
        "0x",
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

      const safeExecutor = accounts[3];

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

    shouldSplitAndMergePositionsOnOutcomeSlots(trader);
  });

  it("should split positions, set outcome slot values, and redeem outcome tokens for conditions", async () => {
    // Mint outcome slots
    const trader = accounts[2];
    const recipient = accounts[7];
    const collateralTokenCount = 10;
    await collateralToken.mint(trader, collateralTokenCount, {
      from: minter
    });
    assert.equal(
      await collateralToken.balanceOf.call(trader),
      collateralTokenCount
    );
    await collateralToken.approve(
      conditionalTokens.address,
      collateralTokenCount,
      { from: trader }
    );

    await conditionalTokens.splitPosition(
      collateralToken.address,
      asciiToHex(0),
      conditionId,
      [0b01, 0b10],
      collateralTokenCount,
      { from: trader }
    );
    assert.equal(
      (await collateralToken.balanceOf.call(
        conditionalTokens.address
      )).valueOf(),
      collateralTokenCount
    );
    assert.equal(await collateralToken.balanceOf.call(trader), 0);

    assert.equal(
      await conditionalTokens.balanceOf.call(
        trader,
        getPositionId(
          collateralToken.address,
          getCollectionId(conditionId, 0b01)
        )
      ),
      collateralTokenCount
    );
    assert.equal(
      await conditionalTokens.balanceOf.call(
        trader,
        getPositionId(
          collateralToken.address,
          getCollectionId(conditionId, 0b10)
        )
      ),
      collateralTokenCount
    );

    // Set outcome in condition
    await conditionalTokens.receiveResult(
      questionId,
      "0x" + [padLeft("3", 64), padLeft("7", 64)].join(""),
      { from: oracle }
    );
    assert.equal(
      await conditionalTokens.payoutDenominator.call(conditionId),
      10
    );
    assert.equal(
      await conditionalTokens.payoutNumerators.call(conditionId, 0),
      3
    );
    assert.equal(
      await conditionalTokens.payoutNumerators.call(conditionId, 1),
      7
    );

    await conditionalTokens.safeTransferFrom(
      trader,
      recipient,
      getPositionId(
        collateralToken.address,
        getCollectionId(conditionId, 0b01)
      ),
      collateralTokenCount,
      "0x",
      { from: trader }
    );

    const buyerPayout = getParamFromTxEvent(
      await conditionalTokens.redeemPositions(
        collateralToken.address,
        asciiToHex(0),
        conditionId,
        [0b10],
        { from: trader }
      ),
      "payout",
      null,
      "PayoutRedemption"
    );

    assert.equal(buyerPayout.valueOf(), (collateralTokenCount * 7) / 10);
    assert.equal(
      await conditionalTokens.balanceOf.call(
        recipient,
        getPositionId(
          collateralToken.address,
          getCollectionId(conditionId, 0b01)
        )
      ),
      collateralTokenCount
    );
    assert.equal(
      await conditionalTokens.balanceOf.call(
        trader,
        getPositionId(
          collateralToken.address,
          getCollectionId(conditionId, 0b10)
        )
      ),
      0
    );

    const recipientPayout = getParamFromTxEvent(
      await conditionalTokens.redeemPositions(
        collateralToken.address,
        asciiToHex(0),
        conditionId,
        [0b01],
        { from: recipient }
      ),
      "payout",
      null,
      "PayoutRedemption"
    );

    assert.equal(
      (await collateralToken.balanceOf.call(recipient)).toNumber(),
      recipientPayout.valueOf()
    );
    assert.equal(
      (await collateralToken.balanceOf.call(trader)).toNumber(),
      buyerPayout.valueOf()
    );
  });

  it("should redeem outcome tokens in more complex scenarios", async () => {
    // Setup a more complex scenario
    const _oracle = accounts[1];
    const _questionId =
      "0x1234567812345678123456781234567812345678123456781234567812345678";
    const _outcomeSlotCount = 4;
    await conditionalTokens.prepareCondition(
      _oracle,
      _questionId,
      _outcomeSlotCount
    );
    const _conditionId = getConditionId(
      _oracle,
      _questionId,
      _outcomeSlotCount
    );

    assert.equal(await conditionalTokens.getOutcomeSlotCount(_conditionId), 4);
    for (let i = 0; i < 4; i++) {
      assert.equal(
        (await conditionalTokens.payoutNumerators(_conditionId, i)).valueOf(),
        0
      );
    }
    assert.equal(
      (await conditionalTokens.payoutDenominator(_conditionId)).valueOf(),
      0
    );
    assert.notEqual(conditionId, _conditionId);

    // create some buyers and purchase collateralTokens and then some Outcome Slots
    const buyers = [3, 4, 5, 6];
    const collateralTokenCounts = [
      toBN(1e19),
      toBN(1e9),
      toBN(1e18),
      toBN(1000)
    ];
    for (let i = 0; i < buyers.length; i++) {
      await collateralToken.mint(
        accounts[buyers[i]],
        collateralTokenCounts[i],
        {
          from: minter
        }
      );
      assert.equal(
        await collateralToken
          .balanceOf(accounts[buyers[i]])
          .then(res => res.toString()),
        collateralTokenCounts[i]
      );
      await collateralToken.approve(
        conditionalTokens.address,
        collateralTokenCounts[i],
        { from: accounts[buyers[i]] }
      );
      await conditionalTokens.splitPosition(
        collateralToken.address,
        asciiToHex(0),
        _conditionId,
        [0b0001, 0b0010, 0b0100, 0b1000],
        collateralTokenCounts[i],
        { from: accounts[buyers[i]] }
      );
    }

    await assertRejects(
      conditionalTokens.receiveResult(
        _questionId,
        "0x" +
          [
            padLeft("14D", 64), // 333
            padLeft("29A", 64), // 666
            padLeft("1", 64), // 1
            padLeft("0", 64)
          ].join(""),
        { from: accounts[9] }
      ),
      "Transaction should have reverted."
    );

    // resolve the condition
    await conditionalTokens.receiveResult(
      _questionId,
      "0x" +
        [
          padLeft("14D", 64), // 333
          padLeft("29A", 64), // 666
          padLeft("1", 64), // 1
          padLeft("0", 64)
        ].join(""),
      { from: _oracle }
    );
    assert.equal(
      await conditionalTokens.payoutDenominator
        .call(_conditionId)
        .then(res => res.toString()),
      1000
    );

    // assert correct payouts for Outcome Slots
    const payoutsForOutcomeSlots = [333, 666, 1, 0];
    for (let i = 0; i < buyers.length; i++) {
      assert.equal(
        collateralTokenCounts[i].toString(),
        (await conditionalTokens.balanceOf.call(
          accounts[buyers[i]],
          getPositionId(
            collateralToken.address,
            getCollectionId(_conditionId, 1 << i)
          )
        )).toString()
      );
      assert.equal(
        await conditionalTokens.payoutNumerators(_conditionId, i),
        payoutsForOutcomeSlots[i]
      );
      assert.equal(
        await conditionalTokens.payoutDenominator(_conditionId),
        1000
      );
    }

    // assert Outcome Token redemption
    for (let i = 0; i < buyers.length; i++) {
      await conditionalTokens.redeemPositions(
        collateralToken.address,
        asciiToHex(0),
        _conditionId,
        [0b0001, 0b0010, 0b0100, 0b1000],
        { from: accounts[buyers[i]] }
      );
      assert.equal(
        await collateralToken
          .balanceOf(accounts[buyers[i]])
          .then(res => res.toString()),
        collateralTokenCounts[i]
      );
    }
  });
});

contract("Complex splitting and merging scenario #1.", function(accounts) {
  let conditionalTokens,
    collateralToken,
    minter = accounts[0],
    oracle1,
    oracle2,
    oracle3,
    questionId1,
    questionId2,
    questionId3,
    outcomeSlotCount1,
    outcomeSlotCount2,
    outcomeSlotCount3,
    player1,
    player2,
    player3,
    conditionId1,
    conditionId2,
    conditionId3;

  before(async () => {
    conditionalTokens = await ConditionalTokens.deployed();
    collateralToken = await ERC20Mintable.new();

    // prepare condition
    oracle1 = accounts[1];
    oracle2 = accounts[2];
    oracle3 = accounts[3];

    questionId1 =
      "0x1234987612349876123498761234987612349876123498761234987612349876";
    questionId2 =
      "0xcafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe";
    questionId3 =
      "0xab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12";

    outcomeSlotCount1 = 2;
    outcomeSlotCount2 = 3;
    outcomeSlotCount3 = 4;

    player1 = accounts[4];
    player2 = accounts[5];
    player3 = accounts[6];

    await conditionalTokens.prepareCondition(
      oracle1,
      questionId1,
      outcomeSlotCount1
    );
    await conditionalTokens.prepareCondition(
      oracle2,
      questionId2,
      outcomeSlotCount2
    );
    await conditionalTokens.prepareCondition(
      oracle3,
      questionId3,
      outcomeSlotCount3
    );

    conditionId1 = getConditionId(oracle1, questionId1, outcomeSlotCount1);
    conditionId2 = getConditionId(oracle2, questionId2, outcomeSlotCount2);
    conditionId3 = getConditionId(oracle3, questionId3, outcomeSlotCount3);

    await collateralToken.mint(player1, 10000, { from: minter });
    await collateralToken.approve(conditionalTokens.address, 10000, {
      from: player1
    });
    await collateralToken.mint(player2, 10000, { from: minter });
    await collateralToken.approve(conditionalTokens.address, 10000, {
      from: player2
    });
    await collateralToken.mint(player3, 10000, { from: minter });
    await collateralToken.approve(conditionalTokens.address, 10000, {
      from: player3
    });
  });

  it("Invalid initial positions should not give any outcome tokens", async () => {
    await conditionalTokens.splitPosition(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b01],
      toBN(1e19),
      { from: player1 }
    );

    assert.equal(
      await conditionalTokens.balanceOf(
        player1,
        getPositionId(
          collateralToken.address,
          getCollectionId(conditionId1, 0b01)
        )
      ),
      0
    );
    assert.equal(
      await collateralToken.balanceOf.call(player1).then(res => res.toString()),
      10000
    );

    await assertRejects(
      conditionalTokens.splitPosition(
        collateralToken.address,
        0,
        conditionId1,
        [0b01, 0b111],
        toBN(1e19),
        { from: player1 }
      ),
      "Worked with an invalid indexSet."
    );
    await assertRejects(
      conditionalTokens.splitPosition(
        collateralToken.address,
        0,
        conditionId1,
        [0b01, 0b11],
        toBN(1e19),
        { from: player1 }
      ),
      "Worked with an invalid indexSet."
    );
    await assertRejects(
      conditionalTokens.splitPosition(
        collateralToken.address,
        0,
        conditionId1,
        [0b01, 0b11, 0b0],
        toBN(1e19),
        { from: player1 }
      ),
      "Worked with an invalid indexSet."
    );
  });

  it("should not produce any position changes when split on an incomplete set of base conditions", async () => {
    await conditionalTokens.splitPosition(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b10],
      1,
      { from: player3 }
    );
    await conditionalTokens.splitPosition(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b01],
      1,
      { from: player3 }
    );
    const collectionId1 = getCollectionId(conditionId1, 0b01);
    const collectionId2 = getCollectionId(conditionId1, 0b10);
    const positionId1 = getPositionId(collateralToken.address, collectionId1);
    const positionId2 = getPositionId(collateralToken.address, collectionId2);

    assert.equal(
      await conditionalTokens
        .balanceOf(player3, positionId1)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player3, positionId2)
        .then(r => r.toNumber()),
      0
    );
  });

  it("should not be able to merge back into a collateral token from a position without any outcome tokens", async () => {
    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        asciiToHex(0),
        conditionId1,
        [0b01, 0b10],
        1,
        { from: player3 }
      ),
      "If this didn't fail, the user is somehow able to withdraw ethereum from positions with none in it, or they have already ether in that position"
    );

    const collectionId1 = getCollectionId(conditionId1, 0b01);
    const collectionId2 = getCollectionId(conditionId1, 0b10);
    const positionId1 = getPositionId(collateralToken.address, collectionId1);
    const positionId2 = getPositionId(collateralToken.address, collectionId2);

    assert.equal(
      await conditionalTokens
        .balanceOf(player3, positionId1)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player3, positionId2)
        .then(r => r.toNumber()),
      0
    );
  });

  it("Should be able to split and merge in more complex scenarios", async () => {
    // Split on an initial condition
    await conditionalTokens.splitPosition(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b01, 0b10],
      1000,
      { from: player1 }
    );

    const collectionId1 = getCollectionId(conditionId1, 0b01);
    const collectionId2 = getCollectionId(conditionId1, 0b10);
    const positionId1 = getPositionId(collateralToken.address, collectionId1);
    const positionId2 = getPositionId(collateralToken.address, collectionId2);

    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      1000
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId2)
        .then(r => r.toNumber()),
      1000
    );
    assert.equal(
      await conditionalTokens.getOutcomeSlotCount(conditionId2).valueOf(),
      3
    );

    // Split on a non-root Collection Identifier and Condition
    await conditionalTokens.splitPosition(
      collateralToken.address,
      collectionId1,
      conditionId2,
      [0b10, 0b01, 0b100],
      100,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      900
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId2)
        .then(r => r.toNumber()),
      1000
    );

    const collectionId3 = combineCollectionIds([
      collectionId1,
      getCollectionId(conditionId2, 0b10)
    ]);
    const collectionId4 = combineCollectionIds([
      collectionId1,
      getCollectionId(conditionId2, 0b01)
    ]);
    const collectionId5 = combineCollectionIds([
      collectionId1,
      getCollectionId(conditionId2, 0b100)
    ]);
    const positionId3 = getPositionId(collateralToken.address, collectionId3);
    const positionId4 = getPositionId(collateralToken.address, collectionId4);
    const positionId5 = getPositionId(collateralToken.address, collectionId5);

    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      100
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId4)
        .then(r => r.toNumber()),
      100
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId5)
        .then(r => r.toNumber()),
      100
    );

    // Split again on a non-root Collection Identifier and Condition
    await conditionalTokens.splitPosition(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b10, 0b01, 0b100, 0b1000],
      100,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId2)
        .then(r => r.toNumber()),
      1000
    );

    const collectionId6 = combineCollectionIds([
      collectionId3,
      getCollectionId(conditionId3, 0b10)
    ]);
    const collectionId7 = combineCollectionIds([
      collectionId3,
      getCollectionId(conditionId3, 0b01)
    ]);
    const collectionId8 = combineCollectionIds([
      collectionId3,
      getCollectionId(conditionId3, 0b100)
    ]);
    const collectionId9 = combineCollectionIds([
      collectionId3,
      getCollectionId(conditionId3, 0b1000)
    ]);
    const positionId6 = getPositionId(collateralToken.address, collectionId6);
    const positionId7 = getPositionId(collateralToken.address, collectionId7);
    const positionId8 = getPositionId(collateralToken.address, collectionId8);
    const positionId9 = getPositionId(collateralToken.address, collectionId9);

    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId6)
        .then(r => r.toNumber()),
      100
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId7)
        .then(r => r.toNumber()),
      100
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      100
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId9)
        .then(r => r.toNumber()),
      100
    );

    // Merge a full set of Outcome Slots back into conditionId3
    await conditionalTokens.mergePositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b10, 0b01, 0b100, 0b1000],
      50,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId6)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId7)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId9)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      50
    );

    // Merge a partial set of Outcome Slots back
    await conditionalTokens.mergePositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b10, 0b01, 0b1000],
      50,
      { from: player1 }
    );
    const collectionId10 = combineCollectionIds([
      collectionId3,
      getCollectionId(conditionId3, 0b1011)
    ]);
    const positionId10 = getPositionId(collateralToken.address, collectionId10);
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId10)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId6)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId7)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId9)
        .then(r => r.toNumber()),
      0
    );

    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        collectionId3,
        conditionId3,
        [0b10, 0b01, 0b100, 0b1000],
        100,
        { from: player1 }
      ),
      "Invalid merging of more tokens than the positions held did not revent"
    );
    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        collectionId3,
        conditionId3,
        [0b10, 0b01, 0b1000],
        100,
        { from: player1 }
      ),
      "Invalid merging of tokens amounting to more than the positions held happened."
    );

    await conditionalTokens.mergePositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b1011, 0b100],
      25,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId10)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      75
    );

    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        collectionId1,
        conditionId2,
        [0b01, 0b10, 0b100],
        100,
        { from: player1 }
      ),
      "it didn't revert when only partial positions in the set have enough outcomeTokens."
    );

    await conditionalTokens.mergePositions(
      collateralToken.address,
      collectionId1,
      conditionId2,
      [0b01, 0b10, 0b100],
      50,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      950
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId4)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId5)
        .then(r => r.toNumber()),
      50
    );

    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        0,
        conditionId1,
        [0b01],
        100,
        { from: player1 }
      ),
      "Should not merge proper positions back into collateralTokens"
    );
    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        0,
        conditionId1,
        [0b01, 0b10],
        1000,
        { from: player1 }
      ),
      "Should not merge positions that dont hold enough value specified back into collateralTokens"
    );
    await assertRejects(
      conditionalTokens.mergePositions(
        collateralToken.address,
        0,
        conditionId1,
        [0b01, 0b10],
        950,
        { from: player3 }
      ),
      "Should not merge positions from the wrong player back into collateralTokens"
    );

    await conditionalTokens.mergePositions(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b01, 0b10],
      950,
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId2)
        .then(r => r.toNumber()),
      50
    );
    assert.equal(
      await collateralToken.balanceOf(player1).then(r => r.toNumber()),
      9950
    );

    await assertRejects(
      conditionalTokens.redeemPositions(
        collateralToken.address,
        asciiToHex(0),
        conditionId1,
        [0b01, 0b10],
        { from: player1 }
      ),
      "The position is being redeemed before the payouts for the condition have been set."
    );

    await conditionalTokens.receiveResult(
      questionId3,
      "0x" +
        [
          padLeft("14D", 64), // 333
          padLeft("1", 64), // 1
          padLeft("29A", 64), // 666
          padLeft("0", 64)
        ].join(""),
      { from: oracle3 }
    );

    assert.equal(
      await conditionalTokens.payoutDenominator(conditionId3).valueOf(),
      1000
    );
    await assertRejects(
      conditionalTokens.redeemPositions(
        collateralToken.address,
        asciiToHex(0),
        conditionId2,
        [0b01, 0b110],
        { from: player1 }
      ),
      "The position is being redeemed before the payouts for the condition have been set."
    );

    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId10)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId6)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId7)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId9)
        .then(r => r.toNumber()),
      0
    );

    // asserts that if you redeem the wrong indexSets, it won't affect the other indexes.
    await conditionalTokens.redeemPositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b10, 0b01, 0b1000],
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      25
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      25
    );

    await conditionalTokens.redeemPositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b10, 0b01, 0b100],
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId8)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      25 + Math.floor(25 * (666 / 1000))
    );

    await conditionalTokens.redeemPositions(
      collateralToken.address,
      collectionId3,
      conditionId3,
      [0b1011],
      { from: player1 }
    );

    // We have to account for a small fraction of tokens getting stuck in the contract there on payout
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      25 + Math.floor(25 * (666 / 1000 + 334 / 1000)) - 1
    );

    await conditionalTokens.receiveResult(
      questionId2,
      "0x" + [padLeft("FF", 64), padLeft("FF", 64), padLeft("0", 64)].join(""),
      { from: oracle2 }
    );

    await conditionalTokens.redeemPositions(
      collateralToken.address,
      collectionId1,
      conditionId2,
      [0b01, 0b10, 0b100],
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId3)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId4)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId5)
        .then(r => r.toNumber()),
      0
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      49
    );

    await conditionalTokens.receiveResult(
      questionId1,
      "0x" + [padLeft("1", 64), padLeft("0", 64)].join(""),
      { from: oracle1 }
    );
    assert.equal(
      await conditionalTokens.payoutDenominator(conditionId1).valueOf(),
      1
    );

    await conditionalTokens.redeemPositions(
      collateralToken.address,
      asciiToHex(0),
      conditionId1,
      [0b01],
      { from: player1 }
    );
    assert.equal(
      await conditionalTokens
        .balanceOf(player1, positionId1)
        .then(r => r.toNumber()),
      0
    );

    // Missing 1 for the rounding of different outcomes
    assert.equal(
      await collateralToken.balanceOf(player1).then(r => r.toNumber()),
      9999
    );
  });
});

contract(
  "Should be able to partially split and merge in complex scenarios. #2",
  function(accounts) {
    let conditionalTokens,
      collateralToken,
      minter = accounts[0],
      oracle1,
      oracle2,
      oracle3,
      questionId1,
      questionId2,
      questionId3,
      outcomeSlotCount1,
      outcomeSlotCount2,
      outcomeSlotCount3,
      player1,
      player2,
      player3,
      conditionId1,
      conditionId2;

    before(async () => {
      conditionalTokens = await ConditionalTokens.deployed();
      collateralToken = await ERC20Mintable.new({ from: minter });

      // prepare condition
      oracle1 = accounts[1];
      oracle2 = accounts[2];
      oracle3 = accounts[3];

      questionId1 =
        "0x1234987612349876123498761234987612349876123498761234987612349876";
      questionId2 =
        "0xcafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe";
      questionId3 =
        "0xab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12";

      outcomeSlotCount1 = 2;
      outcomeSlotCount2 = 3;
      outcomeSlotCount3 = 4;

      player1 = accounts[4];
      player2 = accounts[5];
      player3 = accounts[6];

      await conditionalTokens.prepareCondition(
        oracle1,
        questionId1,
        outcomeSlotCount1
      );
      await conditionalTokens.prepareCondition(
        oracle2,
        questionId2,
        outcomeSlotCount2
      );
      await conditionalTokens.prepareCondition(
        oracle3,
        questionId3,
        outcomeSlotCount3
      );

      conditionId1 = getConditionId(oracle1, questionId1, outcomeSlotCount1);
      conditionId2 = getConditionId(oracle2, questionId2, outcomeSlotCount2);

      await collateralToken.mint(player1, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player1
      });
      await collateralToken.mint(player2, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player2
      });
      await collateralToken.mint(player3, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player3
      });
    });

    it("Should correctly and safely partially split and merge in complex scnarios.", async () => {
      await conditionalTokens.splitPosition(
        collateralToken.address,
        asciiToHex(0),
        conditionId1,
        [0b01, 0b10],
        toBN(1e19),
        { from: player1 }
      );

      const collectionId1 = getCollectionId(conditionId1, 0b01);
      const collectionId2 = getCollectionId(conditionId1, 0b10);
      const positionId1 = getPositionId(collateralToken.address, collectionId1);
      const positionId2 = getPositionId(collateralToken.address, collectionId2);

      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId1),
          "ether"
        ),
        10
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId2),
          "ether"
        ),
        10
      );
      assert.equal(
        fromWei(await collateralToken.balanceOf(player1), "ether"),
        0
      );

      await assertRejects(
        conditionalTokens.splitPosition(
          collateralToken.address,
          collectionId2,
          conditionId2,
          [0b01, 0b10],
          1000,
          { from: player1 }
        ),
        "partial split without having the added positions (3) tokens should be rejected"
      );

      await assertRejects(
        conditionalTokens.splitPosition(
          collateralToken.address,
          collectionId2,
          conditionId2,
          [0b100, 0b01],
          1000,
          { from: player1 }
        ),
        "should be rejected"
      );

      await conditionalTokens.splitPosition(
        collateralToken.address,
        collectionId2,
        conditionId2,
        [0b110, 0b01],
        toBN(1e19),
        { from: player1 }
      );
      const collectionId3 = combineCollectionIds([
        collectionId2,
        getCollectionId(conditionId2, 0b110)
      ]);
      const collectionId4 = combineCollectionIds([
        collectionId2,
        getCollectionId(conditionId2, 0b01)
      ]);
      const positionId3 = getPositionId(collateralToken.address, collectionId3);
      const positionId4 = getPositionId(collateralToken.address, collectionId4);

      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId3),
          "ether"
        ),
        10
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId4),
          "ether"
        ),
        10
      );

      await conditionalTokens.splitPosition(
        collateralToken.address,
        collectionId2,
        conditionId2,
        [0b100, 0b10],
        toBN(1e19),
        { from: player1 }
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId3),
          "ether"
        ),
        0
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId4),
          "ether"
        ),
        10
      );

      const collectionId5 = combineCollectionIds([
        collectionId2,
        getCollectionId(conditionId2, 0b100)
      ]);

      const collectionId6 = combineCollectionIds([
        collectionId2,
        getCollectionId(conditionId2, 0b10)
      ]);
      const positionId5 = getPositionId(collateralToken.address, collectionId5);
      const positionId6 = getPositionId(collateralToken.address, collectionId6);
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId5),
          "ether"
        ),
        10
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId6),
          "ether"
        ),
        10
      );

      await conditionalTokens.mergePositions(
        collateralToken.address,
        collectionId2,
        conditionId2,
        [0b01, 0b10],
        toBN(1e19),
        { from: player1 }
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId6),
          "ether"
        ),
        0
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId4),
          "ether"
        ),
        0
      );

      const collectionId7 = combineCollectionIds([
        collectionId2,
        getCollectionId(conditionId2, 0b11)
      ]);
      const positionId7 = getPositionId(collateralToken.address, collectionId7);
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId7),
          "ether"
        ),
        10
      );
    });
  }
);

contract(
  "The same positions in different orders should equal each other.",
  function(accounts) {
    let conditionalTokens,
      collateralToken,
      minter = accounts[0],
      oracle1,
      oracle2,
      oracle3,
      questionId1,
      questionId2,
      questionId3,
      outcomeSlotCount1,
      outcomeSlotCount2,
      outcomeSlotCount3,
      player1,
      player2,
      player3,
      conditionId1,
      conditionId2;

    before(async () => {
      conditionalTokens = await ConditionalTokens.deployed();
      collateralToken = await ERC20Mintable.new({ from: minter });

      // prepare condition
      oracle1 = accounts[1];
      oracle2 = accounts[2];
      oracle3 = accounts[3];

      questionId1 =
        "0x1234987612349876123498761234987612349876123498761234987612349876";
      questionId2 =
        "0xcafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe";
      questionId3 =
        "0xab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12";

      outcomeSlotCount1 = 2;
      outcomeSlotCount2 = 3;
      outcomeSlotCount3 = 4;

      player1 = accounts[4];
      player2 = accounts[5];
      player3 = accounts[6];

      await conditionalTokens.prepareCondition(
        oracle1,
        questionId1,
        outcomeSlotCount1
      );
      await conditionalTokens.prepareCondition(
        oracle2,
        questionId2,
        outcomeSlotCount2
      );
      await conditionalTokens.prepareCondition(
        oracle3,
        questionId3,
        outcomeSlotCount3
      );

      conditionId1 = getConditionId(oracle1, questionId1, outcomeSlotCount1);
      conditionId2 = getConditionId(oracle2, questionId2, outcomeSlotCount2);

      await collateralToken.mint(player1, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player1
      });
      await collateralToken.mint(player2, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player2
      });
      await collateralToken.mint(player3, toBN(1e19), { from: minter });
      await collateralToken.approve(conditionalTokens.address, toBN(1e19), {
        from: player3
      });
    });

    it("Should create positions in opposite orders that equal each others values", async () => {
      await conditionalTokens.splitPosition(
        collateralToken.address,
        asciiToHex(0),
        conditionId1,
        [0b01, 0b10],
        toBN(1e18),
        { from: player1 }
      );
      await conditionalTokens.splitPosition(
        collateralToken.address,
        asciiToHex(0),
        conditionId2,
        [0b01, 0b10, 0b100],
        toBN(1e18),
        { from: player1 }
      );

      const collectionId1 = getCollectionId(conditionId1, 0b01);
      const collectionId2 = getCollectionId(conditionId1, 0b10);
      const positionId1 = getPositionId(collateralToken.address, collectionId1);
      const positionId2 = getPositionId(collateralToken.address, collectionId2);

      const collectionId3 = getCollectionId(conditionId2, 0b001);
      const collectionId4 = getCollectionId(conditionId2, 0b010);
      const collectionId5 = getCollectionId(conditionId2, 0b100);
      const positionId3 = getPositionId(collateralToken.address, collectionId3);
      const positionId4 = getPositionId(collateralToken.address, collectionId4);
      const positionId5 = getPositionId(collateralToken.address, collectionId5);

      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId1),
          "ether"
        ),
        1
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId2),
          "ether"
        ),
        1
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId3),
          "ether"
        ),
        1
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId4),
          "ether"
        ),
        1
      );
      assert.equal(
        fromWei(
          await conditionalTokens.balanceOf(player1, positionId5),
          "ether"
        ),
        1
      );

      assert.equal(
        fromWei(await collateralToken.balanceOf(player1), "ether"),
        8
      );

      await conditionalTokens.splitPosition(
        collateralToken.address,
        collectionId1,
        conditionId2,
        [0b10, 0b01, 0b100],
        toBN(1e18),
        { from: player1 }
      );
      await conditionalTokens.splitPosition(
        collateralToken.address,
        collectionId4,
        conditionId1,
        [0b10, 0b01],
        toBN(1e18),
        { from: player1 }
      );
      // PositionId1 split on (PositionId4) should equal (PositionId4) split on PositionId1
      const collectionId6 = combineCollectionIds([
        collectionId1,
        getCollectionId(conditionId2, 0b10)
      ]);
      const positionId6 = getPositionId(collateralToken.address, collectionId6);

      const collectionId7 = combineCollectionIds([
        collectionId4,
        getCollectionId(conditionId1, 0b01)
      ]);
      const positionId7 = getPositionId(collateralToken.address, collectionId7);

      assert.equal(positionId6, positionId7);
    });
  }
);
