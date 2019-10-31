Motivation
==========

Conditional tokens were originally designed to enable combinatorial prediction markets more fully. These sorts of markets enable deeper information discovery with respect to conditional probabilities of events and conditional expected values. Prediction markets like this may be represented by nesting traditional prediction markets in systems like Augur or the first version of Gnosis prediction market contracts. However, they weren't designed to maximize fungibility in deeper combinatorial markets. 

Existing Approach to Combinatorial Markets
------------------------------------------

For example, let's suppose there are two oracles which report on the following questions:

1. Which **choice** out of Alice, Bob, and Carol will be made?
2. Will the **score** be high or low?

There are two ways to create conditional tokens backed by a collateral token denoted as ``$``, where the value of these conditional tokens depend on *both* of the reports of these oracles on their respective assigned questions:

.. figure:: /_static/v1-cond-market-abc-hilo.png
    :alt: Markets where events depending on the outcome of the "score" question use outcome tokens from an event depending on the "choice" question as collateral
    :align: center

    **Choice**, then **Score**

.. figure:: /_static/v1-cond-market-hilo-abc.png
    :alt: Another setup where instead events depending on the outcome of the "choice" question use outcome tokens from an event depending on the "score" question as collateral
    :align: center

    **Score**, then **Choice**

Although the outcome tokens in the second layer should represent value in collateral under the same conditions irrespective of the order in which the conditions are specified, they are in reality separate entities. Users may hold separate balances of each even though that balance should theoretically be redeemable under the same conditions.

.. figure:: /_static/v1-cond-market-ot-compare.png
    :alt: The two different conditional tokens which resolves to collateral if Alice gets chosen and the score is high.
    :align: center

    These tokens should be the same, but aren't.

The order in which operations are done on these "deeper" tokens matters as well. For example, partial redemptions to the first layer are only possible if that specific outcome token's second layer condition has been resolved.

Combinatorial Markets with Conditional Tokens
---------------------------------------------

For conditional tokens, because all conditions are held in a single contract and are not tied to a specific collateral token, fungibility in deeper layers may be preserved. Referring to the example, the situation using conditional tokens looks more like this:

.. figure:: /_static/v2-cond-market-slots-only.png
    :alt: The second layer of conditional tokens may resolve to conditional tokens of either condition.
    :align: center

It can be seen that the deeper outcome tokens which were different tokens in older systems are now the same token:

.. figure:: /_static/v2-cond-market-ot-compare.png
    :alt: There is a single class of conditional tokens which resolves to collateral if Alice gets chosen and the score is high.
    :align: center

    Contrast this with the older approach.
