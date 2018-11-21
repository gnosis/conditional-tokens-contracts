Changes from Version 1.x
========================

Documentation for the first version of the prediction market contract framework can be found `here <https://gnosis-pm-contracts.readthedocs.io>`_, or via the menu on the sidebar.


Modular vs Monolithic
---------------------

Modular smart contracts composed v1 of the framework. Various factories for the smart contracts which were integral parts of the system had canonical locations on chain, but were not strictly necessary for using the framework.

In contrast, this version collects all core functionality and storage requirements of prediction markets into a single monolithic instance. Although the property of modularity typically is desired in software projects, on the chain it also comes with the overhead of message passing between contract instances and duplicate code deployments. Consequently, a monolithic design can produce significant gas savings for users of the system.

Furthermore, this aggregation of prediction market data allows for advanced on-chain support of conditional markets.


From Events to Conditions
-------------------------

In v1, the contracts used the term *event* to refer to future events to be resolved by an oracle. These events were represented by contract instances initialized with a nonstandard oracle contract instance and a collateral token address.

Each oracle contract instance was expected to report on a single specific future event. Once the report is ready, the event contract must be notified to pull the result from the oracle.

Furthermore, since event contract instances are tied to single collateral token addresses, a new event contract instance would have to be deployed if support for a different type of collateral token is desired.

The nomenclature clashed with Solidity's use of ``event``, which indicated the definition of a class of EVM logs consumers of contracts could expect to be emitted during transactions with the contract.

In v2, future events to be resolved by an oracle are referred to as *conditions*. These conditions are defined by an oracle account, a question ID, and a outcome slot count.

Any account, whether externally owned or a contract, may act as an oracle. The oracle simply reports the result of the specific question about a future event, which should be retrievable from the question ID, to the monolith.

Because there's no reference to any collateral token in the specification of a condition, the report for the condition applies for all concievable collateral tokens.

Conditional Market Support
~~~~~~~~~~~~~~~~~~~~~~~~~~

In v1, conditional markets may be set up by creating events which uses the outcome tokens of another event as collateral tokens, creating a deeper set of outcome tokens.

For example, let's suppose there are two oracles which report on the following questions:

1. Which **choice** out of Alice, Bob, and Carol will be made?
2. Will the **score** be high or low?

There are two ways to create outcome tokens backed by a collateral token denoted as ``$``, where the value of these outcome tokens depend on *both* of the reports of these oracles on their respective assigned questions:

.. figure:: /_static/v1-cond-market-abc-hilo.png
    :alt: Conditional markets in v1 where events depending on the outcome of the "score" question use outcome tokens from an event depending on the "choice" question as collateral
    :align: center

    **Choice**, then **Score**

.. figure:: /_static/v1-cond-market-hilo-abc.png
    :alt: Another v1 setup where instead events depending on the outcome of the "choice" question use outcome tokens from an event depending on the "score" question as collateral
    :align: center

    **Score**, then **Choice**

Although the outcome tokens in the second layer may have the same value in collateral under the same conditions, they are in reality separate entities:

.. figure:: /_static/v1-cond-market-ot-compare.png
    :alt: The two different outcome tokens which resolves to collateral if Alice gets chosen and the score is high.
    :align: center

    These tokens should be the same, but aren't.

In v2, because all core prediction market data is held in a single contract, and because conditions are not tied to a specific collateral token, this discrepancy may be addressed. The situation in v2 looks more like this:

.. figure:: /_static/v2-cond-market-slots-only.png
    :alt: Conditional markets in v2, where the second layer of outcome tokens may resolve to outcome tokens of either condition.
    :align: center

It can be seen that the outcome tokens from v1 which were different are now the same in v2:

.. figure:: /_static/v2-cond-market-ot-compare.png
    :alt: There is a single class of outcome tokens which resolves to collateral if Alice gets chosen and the score is high.
    :align: center

    Contrast this with v1.


Peripheral Contracts
--------------------

Markets and MarketMakers from v1 are considered not core functionality, and will be moved into dependant packages. The mechanism for CentralizedOracles can now be implemented by regular externally owned accounts. Similarly, MajorityOracles can now be implemented by your preferred multisignature wallets. The FutarchyOracle mechanism is planned to be ported to the new contract system in a separate dependent package. There are no plans to continue support of the Campaign mechanism.
