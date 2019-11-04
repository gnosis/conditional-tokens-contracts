Developer Guide
===============

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

A helper function for determining the condition ID also exists on both the contract and the ``CTHelpers`` library:

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

A outcome collection may be identified with a 32 byte value called a *collection identifier*. Calculating the collection ID for an outcome collection involves hashing its condition ID and index set into a point on the `alt_bn128`_ elliptic curve.

.. note::

    In order to calculate the collection ID for ``(A|B)``, the following steps must be performed.

    1. An initial value for the point x-coordinate is set by hashing the condition ID and the index set of the outcome collection, and interpreting the resulting hash as a big-endian integer.

       .. code-block:: js

            web3.utils.soliditySha3({
                // See section "A Categorical Example" for derivation of this condition ID
                t: 'bytes32',
                v: '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63'
            }, {
                t: 'uint',
                v: 0b011 // Binary Number literals supported in newer versions of JavaScript
            })

       This results in an initial x-coordinate of ``0x52ff54f0f5616e34a2d4f56fb68ab4cc636bf0d92111de74d1ec99040a8da118``, or ``37540785828268254412066351790903087640191294994197155621611396915481249947928``.

       An ``odd`` flag is set according to whether the highest bit of the hash result is set. In this case, because the highest bit of the hash result is not set,``odd = false``.

    2. The x-coordinate gets incremented by one modulo the order of the `alt_bn128`_ base field, which is ``21888242871839275222246405745257275088696311157297823662689037894645226208583``.

       The first time, this results in an updated x-coordinate ``x = 15652542956428979189819946045645812551494983836899331958922359020836023739346``.

    3. The x-coordinate is checked to see if it is the x-coordinate of points on the elliptic curve. Specifically, ``x**3 + 3`` gets computed in the base field, and if the result is a quadratic residue, the x-coordinate belongs to a pair of points on the elliptic curve. If the result is a non-residue however, return to step 2.

       When ``x = 15652542956428979189819946045645812551494983836899331958922359020836023739346``, ``x**3 + 3 == 7181824697751204416624405172148440000524665091599802536460745194285959874882`` is not a quadratic residue in the base field, so go back to step 2.

       When ``x = 15652542956428979189819946045645812551494983836899331958922359020836023739347``, ``x**3 + 3 == 19234863727839675005817902755221636205208068129817953505352549927470359854418`` is also not a quadratic residue in the base field, so go back to step 2.

       When ``x = 15652542956428979189819946045645812551494983836899331958922359020836023739348``, ``x**3 + 3 == 15761946137305644622699047885883332275379818402942977914333319312444771227121`` is still not a quadratic residue in the base field, so go back to step 2.

       When ``x = 15652542956428979189819946045645812551494983836899331958922359020836023739349``, ``x**3 + 3 == 18651314797988388489514246309390803299736227068272699426092091243854420201580`` is a quadratic residue in the base field, so we have found a pair of points on the curve, and we may continue.

    4. Note that the base field occupies 254 bits of space, meaning the x-coordinate we found also occupies 254 bits of space, and has two free bits in an EVM word (256 bits). Leave the highest bit unset, and set the next highest bit if ``odd == true``. In our example, ``odd`` is unset, so we're done, and the collection ID for ``(A|B)`` is ``15652542956428979189819946045645812551494983836899331958922359020836023739349``, or ``0x229b067e142fce0aea84afb935095c6ecbea8647b8a013e795cc0ced3210a3d5``.

We may also combine collection IDs for outcome collections for different conditions by performing elliptic curve point addition on them.

.. note::

    Let's denote the slots for range ends 0 and 1000 from our scalar condition example as ``LO`` and ``HI``. We can find the collection ID for ``(LO)`` to be ``0x560ae373ed304932b6f424c8a243842092c117645533390a3c1c95ff481587c2`` using the procedure illustrated in the previous note.

    The combined collection ID for ``(A|B)&(LO)`` can be calculated in the following manner:

    1. Decompress the constituent collection IDs into elliptic curve point coordinates. Take the low 254 bits as the x-coordinate, and pick the y-coordinate which is even or odd depending on the value of the second highest bit.

       * ``(A|B)``, which has a collection ID of ``0x229b067e142fce0aea84afb935095c6ecbea8647b8a013e795cc0ced3210a3d5``, gets decompressed to the point::

            (15652542956428979189819946045645812551494983836899331958922359020836023739349,
            11459896044816691076313215195950563425899182565928550352639564868174527712586)

         Note the even y-coordinate is chosen here.

       * ``(LO)``, which has a collection ID of ``0x560ae373ed304932b6f424c8a243842092c117645533390a3c1c95ff481587c2``, gets decompressed to the point::

            (9970120961273109372766525305441055537695652051815636823675568206550524069826,
            5871835597783351455285190273403665696556137392019654883787357811704360229175)

         The odd y-coordinate indication bit was chopped off the compressed form before its use as the decompressed form's x-coordinate, and the odd y-coordinate is chosen here.

    2. Perform point addition on the `alt_bn128`_ curve with these points. The sum of these points is the point::

        (21460418698095194776649446887647175906168566678584695492252634897075584178441,
        4596536621806896659272941037410436605631447622293229168614769592376282983323)

    3. Compress the result by taking the x-coordinate, and setting the second highest bit, which should be just outside the x-coordinate, depending on whether the y-coordinate was odd. The combined collection ID for ``(A|B)&(LO)`` is ``0x6f722aa250221af2eba9868fc9d7d43994794177dd6fa7766e3e72ba3c111909``.

.. warning:: Both bitwise XOR and truncated addition is not used in this scenario because these operations are vulnerable to collisions via `a generalized birthday attack`_.

Similar to with conditions, the contract and the ``CTHelpers`` library also provide helper functions for calculating outcome collection IDs:

.. autosolfunction:: ConditionalTokens.getCollectionId

.. _alt_bn128: https://eips.ethereum.org/EIPS/eip-196
.. _a generalized birthday attack: https://link.springer.com/chapter/10.1007/3-540-45708-9_19


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
        v: '0x229b067e142fce0aea84afb935095c6ecbea8647b8a013e795cc0ced3210a3d5'
    })

The ID for ``$:(A|B)`` turns out to be ``0x5355fd8106a08b14aedf99935210b2c22a7f92abaf8bb00b60fcece1032436b7``.

Similarly, the ID for ``$:(LO)`` can be found to be ``0x1958e759291b2bde460cdf2158dea8d0f5c4e22c77ecd09d3ca6a36f01616e02``, and ``$:(A|B)&(LO)`` has an ID of ``0x994b964b94eb15148726de8caa08cac559ec51a90fcbc9cc19aadfdc809f34c9``.

Helper functions for calculating positions also exist:

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

Collateral ``$`` can be split into conditional tokens in positions ``$:(A)``, ``$:(B)``, and ``$:(C)``. To do so, use the following code:

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
        // conditional token in each of the target positions
        amount,
    )

The effect of this transaction is to transfer ``amount`` DollaCoin from the message sender to the ``conditionalTokens`` to hold, and to mint ``amount`` of conditional token for the following positions:

* ``$:(A)``
* ``$:(B)``
* ``$:(C)``

.. note:: The previous example, where collateral was split into shallow positions containing collections with one slot each, is similar to ``Event.buyAllOutcomes`` from Gnosis' first prediction market contracts.

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

This transaction also transfers ``amount`` DollaCoin from the message sender to the ``conditionalTokens`` to hold, but it mints ``amount`` of conditional token for the following positions instead:

* ``$:(B)``
* ``$:(A|C)``

.. warning:: If non-disjoint index sets are supplied to ``splitPosition``, the transaction will revert.

    Partitions must be valid partitions. For example, you can't split ``$`` to ``$:(A|B)`` and ``$:(B|C)`` because ``(A|B)`` (``0b011``) and ``(B|C)`` (``0b110``) share outcome slot ``B`` (``0b010``).

Splits to Deeper Positions
~~~~~~~~~~~~~~~~~~~~~~~~~~

It's also possible to split from a position, burning conditional tokens in that position in order to acquire conditional tokens in deeper positions. For example, you can split ``$:(A|B)`` to target ``$:(A|B)&(LO)`` and ``$:(A|B)&(HI)``:

.. code-block:: js

    await conditionalTokens.splitPosition(
        // Note that we're still supplying the same collateral token
        // even though we're going two levels deep.
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        // Here, instead of just supplying 32 zero bytes, we supply
        // the collection ID for (A|B).
        // This is NOT the position ID for $:(A|B)!
        '0x229b067e142fce0aea84afb935095c6ecbea8647b8a013e795cc0ced3210a3d5',
        // This is the condition ID for the example scalar condition
        '0x3bdb7de3d0860745c0cac9c1dcc8e0d9cb7d33e6a899c2c298343ccedf1d66cf',
        // This is the only partition that makes sense
        // for conditions with only two outcome slots
        [0b01, 0b10],
        amount,
    )

This transaction burns ``amount`` of conditional token in position ``$:(A|B)`` (position ID ``0x5355fd8106a08b14aedf99935210b2c22a7f92abaf8bb00b60fcece1032436b7``) in order to mint ``amount`` of conditional token in the following positions:

* ``$:(A|B)&(LO)``
* ``$:(A|B)&(HI)``

Because the collection ID for ``(A|B)&(LO)`` is just the sum of the collection IDs for ``(A|B)`` and ``(LO)``, we could have split from ``(LO)`` to get ``(A|B)&(LO)`` and ``(C)&(LO)``:

.. code-block:: js

    await conditionalTokens.splitPosition(
        '0xD011ad011ad011AD011ad011Ad011Ad011Ad011A',
        // The collection ID for (LO).
        // This collection contains an outcome collection from the example scalar condition
        // instead of from the example categorical condition.
        '0x560ae373ed304932b6f424c8a243842092c117645533390a3c1c95ff481587c2',
        // This is the condition ID for the example categorical condition
        // as opposed to the example scalar condition.
        '0x67eb23e8932765c1d7a094838c928476df8c50d1d3898f278ef1fb2a62afab63',
        // This partitions { A, B, C } into [{ A, B }, { C }]
        [0b011, 0b100],
        amount,
    )

The ``$:(A|B)&(LO)`` position reached is the same both ways.

.. figure:: /_static/v2-cond-market-ot-compare.png
    :alt: There is a single class of conditional tokens which resolves to collateral if Alice gets chosen and the score is high.
    :align: center

    There are many ways to split to a deep position.

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

Merging positions does precisely the opposite of what splitting a position does. It burns conditional tokens in the deeper positions to either mint conditional tokens in a shallower position or send collateral to the message sender:

.. figure:: /_static/merge-positions.png
    :alt: A couple examples of merging positions.
    :align: center

    Splitting positions, except with the arrows turned around.

To merge positions, use the following function:

.. autosolfunction:: ConditionalTokens.mergePositions

If successful, the function will emit this event:

.. autosolevent:: ConditionalTokens.PositionsMerge

.. note:: This generalizes ``sellAllOutcomes`` from Gnosis' first prediction market contracts like ``splitPosition`` generalizes ``buyAllOutcomes``.


Querying and Transferring Stake
-------------------------------

The ConditionalTokens contract implements the `ERC1155 multitoken`_ interface. In addition to a holder address, each token is indexed by an ID in this standard. In particular, position IDs are used to index conditional tokens. This is reflected in the balance querying function:

.. sol:function:: balanceOf(address owner, uint256 positionId) external view returns (uint256)

To transfer conditional tokens, the following functions may be used, as per ERC1155:

.. sol:function::
    safeTransferFrom(address from, address to, uint256 positionId, uint256 value, bytes data) external
    safeBatchTransferFrom(address from, address to, uint256[] positionIds, uint256[] values, bytes data) external

These transfer functions ignore the ``data`` parameter.

.. note:: When sending to contract accounts, transfers will be rejected unless the recipient implements the ``ERC1155TokenReceiver`` interface and returns the expected magic values. See the `ERC1155 multitoken`_ spec for more information.

Approving an operator account to transfer conditional tokens on your behalf may also be done via:

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
