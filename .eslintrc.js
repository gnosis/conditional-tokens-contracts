module.exports = {
  extends: ["eslint:recommended", "plugin:prettier/recommended"],
  env: {
    node: true,
    mocha: true
  },
  globals: {
    artifacts: true,
    web3: true,
    contract: true,
    assert: true
  },
  parserOptions: { ecmaVersion: 8 }
};
