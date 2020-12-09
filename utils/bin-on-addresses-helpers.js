// To use this, just import this file and supply it with some web3 utils:
//     require("@gnosis.pm/conditional-tokens-contracts/utils/manyid-helpers")(web3.utils)

module.exports = function({ toBN, soliditySha3 }) {
  const TOKEN_CONDITIONAL = 0;
  const TOKEN_DONATED = 2;
  const TOKEN_STAKED = 2;

  const INITIAL_CUSTOMER_BALANCE = toBN("1000").mul(toBN("10").pow(toBN("18")));

  function conditionalTokenId(market, customer) {
    return soliditySha3(
      { t: "uint8", v: TOKEN_CONDITIONAL },
      { t: "uint64", v: market },
      { t: "address", v: customer }
    );
  }

  function collateralDonatedTokenId(collateralToken, market, outcome) {
    return soliditySha3(
      { t: "uint8", v: TOKEN_DONATED },
      { t: "address", v: collateralToken },
      { t: "uint64", v: market },
      { t: "uint64", v: outcome }
    );
  }

  function collateralStakedTokenId(collateralToken, market, outcome) {
    return soliditySha3(
      { t: "uint8", v: TOKEN_STAKED },
      { t: "address", v: collateralToken },
      { t: "uint64", v: market },
      { t: "uint64", v: outcome }
    );
  }

  return {
    conditionalTokenId,
    collateralDonatedTokenId,
    collateralStakedTokenId,
    TOKEN_CONDITIONAL,
    TOKEN_DONATED,
    TOKEN_STAKED,
    INITIAL_CUSTOMER_BALANCE
  };
};
