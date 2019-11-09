Glossary
========

Condition
---------

A condition is a question that a specific oracle reports on with a preset number of outcome slots. It is analogous to an *event* from Gnosis' first prediction market contracts.

A condition's ID may be calculated with the following expression::

    keccak256(oracle . questionId . outcomeSlotCount)

**Oracle**
    The oracle for a condition is the account designated to resolve the condition by reporting the payout values for each outcome slot of the condition.

**Outcome slot**
    Roughly speaking, an outcome slot of a condition is a degree of freedom for the oracle's answer to the question at hand.

    At the resolution of a condition, an oracle reports a payout value for each outcome slot of a condition.

    For example, a condition that will result in one of N outcomes (i.e. categorical markets), may be expressed by N outcome slots, with the expection that the oracle will weight the correct outcome slot with all of the payout, and the incorrect outcome slots with no payout.

    Another example: a condition with an result in some continuous range [A, B] (i.e. scalar markets), may have two outcome slots which correspond to the ends of the range A and B. Both slots are set to receive a proportion of the payout according to how close the outcome X is to A or B.

**Condition resolution**
    Conditions resolve when an oracle submits payout values for all of the condition’s outcome slots. Conditional tokens proportionally redeem to their underlying collateral depending on the payout values set in the condition resolution.


Position
--------

Each conditional token is tied to a position.

To form a position, first decide on the position's collateral token. Then consider a set of conditions. For each of these conditions, take some subset of that condition's outcome slots. Call these subsets outcome collections.

That position's conditional tokens can be redeemed for the collateral token if *every* condition associated with the position resolves in such a manner that all the outcome collections in the position contain some payout value.

Roughly speaking, a position represents the collateral token if each of the position's outcome collections contain the correct outcome.

A position's ID may be calculated with the following expression::

    keccak256(collateralToken . combinedCollectionIdentifier)

where ``combinedCollectionIdentifier`` is an hash of the set of identifiers for each outcome collection (see the developer guide for details).

**Index set**
    A bit array that aids in representing an outcome collection for a condition. Represented as a ``uint256`` parameter, where the lowest bit's state (1) represents whether or not the first outcome slot is included in the set, the next lowest bit's state (2) represents whether or not the second outcome slot is included, the third lowest (4) the third slot's inclusion, etc.

**Partition**
    A way to split up the outcome slots for a condition into outcome collections. Represented by a list of disjoint index sets. The definition comes from mathematics (technically, *singleton partitions* aren't used though).

**Collateral token**
    The ERC20 token backing the position.

**Position depth**
    The number of conditions a position is based off of. Terminology is chosen because positions form a DAG (directed acyclic graph) which is very tree-like. Shallow positions have few conditions, and deep positions have many conditions.

    **Root position**
        A position based off of only a single condition. Pays out depending on the outcome of the condition. Redeems directly as collateral tokens
    
    **Non-root position**
        A position based off of multiple conditions. Pays out depending on all of the outcomes of the multiple conditions. Can be redeemed to shallower positions.

    **Atomic position**
        A position is atomic with respect to a set of conditions if it is contingent on all of the conditions in that set.
