Developer Guide
===============

.. warning::

    This document refers to an experimental prediction market framework under active development. Some things may change. You may also be interested in the predecessor of this work: the original `Gnosis prediction market contracts <https://gnosis-pm-contracts.readthedocs.io>`_.

Prerequisites
-------------

Usage of the ``ConditionalTokens`` smart contract requires some proficiency in `Solidity`_.

Additionally, this guide will assume a `Truffle`_ based setup. Client-side code samples will be written in JavaScript assuming the presence of a `web3.js`_ instance and various `TruffleContract`_ wrappers.

The current state of this smart contract may be found on `Github`_.

.. _Solidity: https://solidity.readthedocs.io
.. _Truffle: https://truffleframework.com
.. _web3.js: https://web3js.readthedocs.io/en/1.0/
.. _TruffleContract: https://github.com/trufflesuite/truffle/tree/next/packages/truffle-contract#truffle-contract
.. _Github: https://github.com/gnosis/conditional-tokens-contracts

Installation
------------

Via NPM
~~~~~~~

This developmental framework may be installed from Github through NPM by running the following::

    npm i '@gnosis.pm/conditional-tokens-contracts'


Preparing a Condition
---------------------

Before conditional tokens can exist, a *condition* must be prepared. A condition is a question to be answered in the future by a specific oracle in a particular manner. The following function may be used to prepare a condition:

.. autosolfunction:: ConditionalTokens.prepareCondition

.. note:: It is up to the consumer of the contract to interpret the question ID correctly. For example, a client may interpret the question ID as an IPFS hash which can be used to retrieve a document specifying the question more fully. The meaning of the question ID is left up to clients.

If the function succeeds, the following event will be emitted, signifying the preparation of a condition:

.. autosolevent:: ConditionalTokens.ConditionPreparation

.. note:: The condition ID is different from the question ID, and their distinction is important.

The successful preparation of a condition also initializes the following state variable:

.. autosolstatevar:: ConditionalTokens.payoutNumerators

To determine if, given a condition's ID, a condition has been prepared, or to find out a condition's outcome slot count, use the following accessor:

.. autosolfunction:: ConditionalTokens.getOutcomeSlotCount

The resultant payout vector of a condition contains a predetermined number of *outcome slots*. The entries of this vector are reported by the oracle, and their values sum up to one. This payout vector may be interpreted as the oracle's answer to the question posed in the condition.

A Categorical Example
~~~~~~~~~~~~~~~~~~~~~

Let's consider a question where only one out of multiple choices may be chosen:

    Who out of the following will be chosen?

    * Alice
    * Bob
    * Carol

Through some commonly agreed upon mechanism, the detailed description for this question becomes strongly associated with a 32 byte question ID: ``0xabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc1234``

Let's also suppose we trust the oracle with address ``0x1337aBcdef1337abCdEf1337ABcDeF1337AbcDeF`` to deliver the answer for this question.

To prepare this condition, the following code gets run:

.. code-block:: js

    await conditionalTokens.prepareCondition(
        '0x1337aBcdef1337abCdEf1337ABcDeF1337AbcDeF',
        '0xabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc1234',
        3
    )

The condition ID may be determined off-chain from the parameters via ``web3``:

.. code-block:: js

    web3.utils.soliditySha3({
        t: 'address',
        v: '0x1337aBcdef1337abCdEf1337ABcDeF1337AbcDeF'
    }, {
        t: 'bytes32',
        v: '0xabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc1234'
    }, {
        t: 'uint',
        v: 3
    })

A helper function for determining the condition ID also exists on the contract:

.. autosolfunction:: ConditionalTokens.getConditionId

This yields a condition ID of ``0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63``.

Later, if the oracle ``0x1337aBcdef1337abCdEf1337ABcDeF1337AbcDeF`` makes a report that the payout vector for the condition is ``[0, 1, 0]``, the oracle essentially states that Bob was chosen, as the outcome slot associated with Bob would receive all of the payout.

A Scalar Example
~~~~~~~~~~~~~~~~

Let us now consider a question where the answer may lie in a range:

    What will the score be? [0, 1000]

Let's say the question ID for this question is ``0x777def777def777def777def777def777def777def777def777def777def7890``, and that we trust the oracle ``0xCafEBAbECAFEbAbEcaFEbabECAfebAbEcAFEBaBe`` to deliver the results for this question.

To prepare this condition, the following code gets run:

.. code-block:: js

    await conditionalTokens.prepareCondition(
        '0xCafEBAbECAFEbAbEcaFEbabECAfebAbEcAFEBaBe',
        '0x777def777def777def777def777def777def777def777def777def777def7890',
        2
    )

The condition ID for this condition can be calculated as ``0x3bdb7de3d0860745c0cac9c1dcc8e0d9cb7d33e6a899c2c298343ccedf1d66cf``.

In this case, the condition was created with two slots: one which represents the low end of the range (0) and another which represents the high end (1000). The slots' reported payout values should indicate how close the answer was to these endpoints. For example, if the oracle ``0xCafEBAbECAFEbAbEcaFEbabECAfebAbEcAFEBaBe`` makes a report that the payout vector is ``[9/10, 1/10]``, then the oracle essentially states that the score was 100, as the slot corresponding to the low end is worth nine times what the slot corresponding with the high end is worth, meaning the score should be nine times closer to 0 than it is close to 1000. Likewise, if the payout vector is reported to be ``[0, 1]``, then the oracle is saying that the score was *at least* 1000.


Outcome Collections
-------------------

The main concept for understanding the mechanics of this system is that of a *position*. We will build to this concept from conditions and outcome slots, and then demonstrate the use of this concept.

However, before we can talk about positions, we first have to talk about *outcome collections*, which may be defined like so:

    A nonempty proper subset of a condition’s outcome slots which represents the sum total of all the contained slots’ payout values.

Categorical Example Featuring Alice, Bob, and Carol
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

We'll denote the outcome slots for Alice, Bob, and Carol as ``A``, ``B``, and ``C`` respectively.

A valid outcome collection may be ``(A|B)``. In this example, this outcome collection represents the eventuality in which either Alice or Bob is chosen. Note that for a categorical condition, the payout vector which the oracle reports will eventually contain a one in exactly one of the three slots, so the sum of the values in Alice's and Bob's slots is one precisely when either Alice or Bob is chosen, and zero otherwise.

``(C)`` by itself is also a valid outcome collection, and this simply represents the case where Carol is chosen.

``()`` is an invalid outcome collection, as it is empty. Empty outcome collections do not make sense, as they would essentially represent no eventuality and have no value no matter what happens.

Conversely, ``(A|B|C)`` is also an invalid outcome collection, as it is not a proper subset. Outcome collections consisting of all the outcome slots for a condition also do not make sense, as they would simply represent any eventuality, and should be equivalent to whatever was used to collateralize these outcome collections.

Finally, outcome slots from different conditions (e.g. ``(A|X)``) cannot be composed in a single outcome collection.

Index Set Representation and Identifier Derivation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A outcome collection may be represented by an a condition and an *index set*. This is a 256 bit array which denotes which outcome slots are present in a outcome collection. For example, the value ``3 == 0b011`` corresponds to the outcome collection ``(A|B)``, whereas the value ``4 == 0b100`` corresponds to ``(C)``. Note that the indices start at the lowest bit in a ``uint``.

A outcome collection may be identified with a 32 byte value called a *collection identifier*. In order to calculate the collection ID for ``(A|B)``, simply hash the condition ID and the index set:

.. code-block:: js

    web3.utils.soliditySha3({
        // See section "A Categorical Example" for derivation of this condition ID
        t: 'bytes32',
        v: '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63'
    }, {
        t: 'uint',
        v: 0b011 // Binary Number literals supported in newer versions of JavaScript
    })

This results in a collection ID of ``0x52ff54f0f5616e34a2d4f56fb68ab4cc636bf0d92111de74d1ec99040a8da118``.

We may also combine collection IDs for outcome collections for different conditions by adding their values modulo 2^256 (equivalently, by adding their values and then taking the lowest 256 bits).

To illustrate, let's denote the slots for range ends 0 and 1000 from our scalar condition example as ``LO`` and ``HI``. We can find the collection ID for ``(LO)`` to be ``0xd79c1d3f71f6c9d998353ba2a848e596f0c6c1a9f6fa633f2c9ec65aaa097cdc``.

The combined collection ID for ``(A|B)&(LO)`` can be calculated via:

.. code-block:: js

    '0x' + BigInt.asUintN(256,
        0x52ff54f0f5616e34a2d4f56fb68ab4cc636bf0d92111de74d1ec99040a8da118n +
        0xd79c1d3f71f6c9d998353ba2a848e596f0c6c1a9f6fa633f2c9ec65aaa097cdcn
    ).toString(16)

.. note:: `BigInt`_ is used here for the calculation, though `BN.js`_ or `BigNumber.js`_ should both also suffice.

This calculation yields the value ``0x2a9b72306758380e3b0a31125ed39a635432b283180c41b3fe8b5f5eb4971df4``.

Similar to with conditions, the contract also provides a helper function for calculating outcome collection IDs:

.. autosolfunction:: ConditionalTokens.getCollectionId

.. _BigInt: https://tc39.github.io/proposal-bigint/
.. _BN.js: https://github.com/indutny/bn.js/
.. _BigNumber.js: https://github.com/MikeMcl/bignumber.js/


Defining Positions
------------------

In order to define a position, we first need to designate a collateral token. This token must be an `ERC20`_ token which exists on the same chain as the ConditionalTokens instance.

Then we need at least one condition with a outcome collection, though a position may refer to multiple conditions each with an associated outcome collection. Positions become valuable precisely when *all* of its constituent outcome collections are valuable. More explicitly, the value of a position is a *product* of the values of those outcome collections composing the position.

With these ingredients, position identifiers can also be calculated by hashing the address of the collateral token and the combined collection ID of all the outcome collections in the position. We say positions are *deeper* if they contain more conditions and outcome collections, and *shallower* if they contain less.

As an example, let's suppose that there is an ERC20 token called DollaCoin which exists at the address ``0xD011ad011ad011AD011ad011Ad011Ad011Ad011A``, and it is used as collateral for some positions. We will denote this token with ``$``.

We may calculate the position ID for the position ``$:(A|B)`` via:

.. code-block:: js

    web3.utils.soliditySha3({
        t: 'address',
        v: '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A'
    }, {
        t: 'bytes32',
        v: '0x52ff54f0f5616e34a2d4f56fb68ab4cc636bf0d92111de74d1ec99040a8da118'
    })

The ID for ``$:(A|B)`` turns out to be ``0x6147e75d1048cea497aeee64d1a4777e286764ded497e545e88efc165c9fc4f0``.

Similarly, the ID for ``$:(LO)`` can be found to be ``0xfdad82d898904026ae6c01a5800c0a8ee9ada7e7862f9bb6428b6f81e06f53bb``, and ``$:(A|B)&(LO)`` has an ID of ``0xcc77e750b61d29e158aa3193faa3673b2686ba9f6a16f51b5cdbea2a4f694be0``.

A helper function for calculating positions also exists:

.. autosolfunction:: ConditionalTokens.getPositionId

.. _ERC20: https://theethereum.wiki/w/index.php/ERC20_Token_Standard

All the positions backed by DollaCoin which depend on the example categorical condition and the example scalar condition form a DAG (directed acyclic graph):

.. figure:: /_static/all-positions-from-two-conditions.png
    :alt: DAG of every position which can be made from DollaCoin and the two example conditions, where the nodes are positions, edges are colored by condition, and directionality is implied with vertical spacing.
    :align: center

    Graph of all positions backed by ``$`` which are contingent on either or both of the example conditions.


Splitting and Merging Positions
-------------------------------

Once conditions have been prepared, stake in positions contingent on these conditions may be obtained. Furthermore, this stake must be backed by collateral held by the contract. In order to ensure this is the case, stake in shallow positions may only be minted by sending collateral to the contract for the contract to hold, and stake in deeper positions may only be created by burning stake in shallower positions. Any of these is referred to as *splitting a position*, and is done through the following function:

.. autosolfunction:: ConditionalTokens.splitPosition

If this transaction does not revert, the following event will be emitted:

.. autosolevent:: ConditionalTokens.PositionSplit

To decipher this function, let's consider what would be considered a valid split, and what would be invalid:

.. figure:: /_static/valid-vs-invalid-splits.png
    :alt: Various valid and invalid splits of positions.
    :align: center

    Details for some of these scenarios will follow

Basic Splits
~~~~~~~~~~~~

Collateral ``$`` can be split into outcome tokens in positions ``$:(A)``, ``$:(B)``, and ``$:(C)``. To do so, use the following code:

.. code-block:: js

    const amount = 1e18 // could be any amount

    // user must allow conditionalTokens to
    // spend amount of DollaCoin, e.g. through
    // await dollaCoin.approve(conditionalTokens.address, amount)

    await conditionalTokens.splitPosition(
        // This is just DollaCoin's address
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        // For splitting from collateral, pass bytes32(0)
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        // "Choice" condition ID:
        // see A Categorical Example for derivation
        '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63',
        // Each element of this partition is an index set:
        // see Outcome Collections for explanation
        [0b001, 0b010, 0b100],
        // Amount of collateral token to submit for holding
        // in exchange for minting the same amount of
        // outcome token in each of the target positions
        amount,
    )

The effect of this transaction is to transfer ``amount`` DollaCoin from the message sender to the ``conditionalTokens`` to hold, and to mint ``amount`` of outcome token for the following positions:

========= ======================================================================
 Symbol                               Position ID
========= ======================================================================
``$:(A)`` ``0x8c12fa3bb72c9c455acd4d6034989ec0ce9188afd7c89c8c42d064ed7fe5a9d8``
``$:(B)`` ``0x21aec03d8dfd8b5f0a2750718fe491e439f3625816e383b66a05cabd56624b4c``
``$:(C)`` ``0x8085f7c500098412ff2fc701a74174527e7b39a2b923cd0bca6ad2d5f7fa348d``
========= ======================================================================

.. note:: The previous example, where collateral was split into shallow positions containing collections with one slot each, is similar to ``Event.buyAllOutcomes`` from v1.

The set of ``(A)``, ``(B)``, and ``(C)`` is not the only nontrivial partition of outcome slots for the example categorical condition. For example, the set ``(B)`` (with index set ``0b010``) and ``(A|C)`` (with index set ``0b101``) also partitions these outcome slots, and consequently, splitting from ``$`` to ``$:(B)`` and ``$:(A|C)`` is also valid and can be done with the following code:

.. code-block:: js

    await conditionalTokens.splitPosition(
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63',
        // This partition differs from the previous example
        [0b010, 0b101],
        amount,
    )

This transaction also transfers ``amount`` DollaCoin from the message sender to the ``conditionalTokens`` to hold, but it mints ``amount`` of outcome token for the following positions instead:

=========== ======================================================================
  Symbol                                  Position ID
=========== ======================================================================
``$:(B)``   ``0x21aec03d8dfd8b5f0a2750718fe491e439f3625816e383b66a05cabd56624b4c``
``$:(A|C)`` ``0xb33b3d0035913315b76e85842f682920f78b32c43c7175768c4c67e3f31e6413``
=========== ======================================================================

.. warning:: If non-disjoint index sets are supplied to ``splitPosition``, the transaction will revert.

    Partitions must be valid partitions. For example, you can't split ``$`` to ``$:(A|B)`` and ``$:(B|C)`` because ``(A|B)`` (``0b011``) and ``(B|C)`` (``0b110``) share outcome slot ``B`` (``0b010``).

Splits to Deeper Positions
~~~~~~~~~~~~~~~~~~~~~~~~~~

It's also possible to split from a position, burning outcome tokens in that position in order to acquire outcome tokens in deeper positions. For example, you can split ``$:(A|B)`` to target ``$:(A|B)&(LO)`` and ``$:(A|B)&(HI)``:

.. code-block:: js

    await conditionalTokens.splitPosition(
        // Note that we're still supplying the same collateral token
        // even though we're going two levels deep.
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        // Here, instead of just supplying 32 zero bytes, we supply
        // the collection ID for (A|B).
        // This is NOT the position ID for $:(A|B)!
        '0x52ff54f0f5616e34a2d4f56fb68ab4cc636bf0d92111de74d1ec99040a8da118',
        // This is the condition ID for the example scalar condition
        '0x3bdb7de3d0860745c0cac9c1dcc8e0d9cb7d33e6a899c2c298343ccedf1d66cf',
        // This is the only partition that makes sense
        // for conditions with only two outcome slots
        [0b01, 0b10],
        amount,
    )

This transaction burns ``amount`` of outcome token in position ``$:(A|B)`` (position ID ``0x6147e75d1048cea497aeee64d1a4777e286764ded497e545e88efc165c9fc4f0``) in order to mint ``amount`` of outcome token in the following positions:

================ ======================================================================
  Symbol                                  Position ID
================ ======================================================================
``$:(A|B)&(LO)`` ``0xcc77e750b61d29e158aa3193faa3673b2686ba9f6a16f51b5cdbea2a4f694be0``
``$:(A|B)&(HI)`` ``0xbacf3ddf0474d567cd254ea0674fe52ab20a3e2ebca00ec71a846f3c48c5de9d``
================ ======================================================================

Splits on Partial Partitions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Supplying a partition which does not cover the set of all outcome slots for a condition, but instead some outcome collection, is also possible. For example, it is possible to split ``$:(B|C)`` (position ID ``0x5d06cd85e2ff915efab0e7881432b1c93b3e543c5538d952591197b3893f5ce3``) to ``$:(B)`` and ``$:(C)``:

.. code-block:: js

    await conditionalTokens.splitPosition(
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        // Note that we also supply zeroes here, as the only aspect shared
        // between $:(B|C), $:(B) and $:(C) is the collateral token
        '0x0000000000000000000000000000000000000000000000000000000000000000',
        '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63',
        // This partition does not cover the first outcome slot
        [0b010, 0b100],
        amount,
    )

Merging Positions
~~~~~~~~~~~~~~~~~

Merging positions does precisely the opposite of what splitting a position does. It burns outcome tokens in the deeper positions to either mint outcome tokens in a shallower position or send collateral to the message sender:

.. figure:: /_static/merge-positions.png
    :alt: A couple examples of merging positions.
    :align: center

    Splitting positions, except with the arrows turned around.

To merge positions, use the following function:

.. autosolfunction:: ConditionalTokens.mergePositions

If successful, the function will emit this event:

.. autosolevent:: ConditionalTokens.PositionsMerge

.. note:: This generalizes ``sellAllOutcomes`` from v1 like ``splitPosition`` generalizes ``buyAllOutcomes``.


Querying and Transferring Stake
-------------------------------

Outcome tokens in positions are not ERC20 tokens, but rather part of an `ERC1155 multitoken`_.

In addition to a holder address, each token is indexed by an ID in this standard. In particular, position IDs are used to index outcome tokens. This is reflected in the balance querying function:

.. sol:function:: balanceOf(address owner, uint256 positionId) external view returns (uint256)

To transfer outcome tokens, the following functions may be used, as per ERC1155:

.. sol:function::
    safeTransferFrom(address from, address to, uint256 positionId, uint256 value, bytes data) external
    safeBatchTransferFrom(address from, address to, uint256[] positionIds, uint256[] values, bytes data) external

These transfer functions ignore the ``data`` parameter.

.. note:: When sending to contract accounts, transfers will be rejected unless the recipient implements the ``ERC1155TokenReceiver`` interface and returns the expected magic values. See the `ERC1155 multitoken`_ spec for more information.

Approving an operator account to transfer outcome tokens on your behalf may also be done via:

.. sol:function:: setApprovalForAll(address operator, bool approved) external

Querying the status of approval can be done with:

.. sol:function:: isApprovedForAll(address owner, address operator) external view returns (bool)

.. _ERC1155 multitoken: https://eips.ethereum.org/EIPS/eip-1155


Redeeming Positions
-------------------

Before this is possible, the payout vector must be set by the oracle:

.. autosolfunction:: ConditionalTokens.reportPayouts

This will emit the following event:

.. autosolevent:: ConditionalTokens.ConditionResolution

Then positions containing this condition can be redeemed via:

.. autosolfunction:: ConditionalTokens.redeemPositions

This will trigger the following event:

.. autosolevent:: ConditionalTokens.PayoutRedemption

Also look at this chart:

.. figure:: /_static/redemption.png
    :alt: Oracle reporting and corresponding redemption rates.
    :align: center
