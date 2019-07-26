Contributing
============

The source for the contracts can be found on `Github`_.

.. _Github: https://github.com/gnosis/conditional-tokens-contracts

.. highlight:: bash

To set up for contributing, install requirements with NPM::

   npm install

.. tip:: Many of the following commands simply wrap corresponding `Truffle commands <https://truffleframework.com/docs/truffle/reference/truffle-commands>`_.


Testing and Linting
-------------------

The test suite may be run using::

   npm test

In order to run a subset of test cases which match a regular expression, the ``TEST_GREP`` environment variable may be used::

   TEST_GREP='obtainable conditionIds' npm test

The JS test files may be linted via::

   npm run lint

Contracts may also be linted via::

   npm run lint-contracts

.. _Truffle: https://truffleframework.com


Development commands
--------------------

To compile all the contracts, obtaining build artifacts containing each containing their respective contract's ABI and bytecode, use the following command::

   npm run compile

Running the migrations, deploying the contracts onto a chain and recording the contract's deployed location in the build artifact can also be done::

   npm run migrate

Dropping into a Truffle develop session can be done via::

   npm run develop


Network Information
-------------------

Showing the deployed addresses of all contracts on all networks can be done via::

   npm run networks

Extra command line options for the underlying Truffle command can be passed down through NPM by preceding the options list with ``--``. For example, in order to purge the build artifacts of any unnamed network information, you can run::

   npm run networks -- --clean

To take network info from ``networks.json`` and inject it into the build artifacts, you can run::

   npm run injectnetinfo

If you instead wish to extract all network information from the build artifacts into ``networks.json``, run::

   npm run extractnetinfo

.. warning:: Extracting network info will overwrite ``networks.json``.


Building the Documentation
--------------------------

(Will install `Sphinx <http://www.sphinx-doc.org/en/stable/>`_ and `Solidity Domain for Sphinx <https://github.com/cag/sphinxcontrib-soliditydomain/>`_):

.. code-block:: bash

   cd docs
   pip install -r requirements.txt
   make html


Contributors
------------

* Stefan George (`Georgi87 <https://github.com/Georgi87>`_)
* Martin Koeppelmann (`koeppelmann <https://github.com/koeppelmann>`_)
* Alan Lu (`cag <https://github.com/cag>`_)
* Roland Kofler (`rolandkofler <https://github.com/rolandkofler>`_)
* Collin Chin (`collinc97 <https://github.com/collinc97>`_)
* Christopher Gewecke (`cgewecke <https://github.com/cgewecke>`_)
* Anton V Shtylman (`InfiniteStyles <https://github.com/InfiniteStyles>`_)
* Billy Rennekamp (`okwme <https://github.com/okwme>`_)
* Denis Granha (`denisgranha <https://github.com/denisgranha>`_)
* Alex Beregszaszi (`axic <https://github.com/axic>`_)
