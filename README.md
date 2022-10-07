# Hands-on Exercise: Flash Loan based Liquidation

## Tips

- If not enough profit after calling liquidate once, next time liquidate up to 49%, then liquidate again
  Helpful resource: https://github.com/haydenshively/Nantucket/blob/master/contracts/Liquidator.sol

## Quickstart

1. Start docker desktop
2. `git clone https://github.com/AlbertSu123/defi-mooc-lab.git`
3. In the first terminal, run `docker build -t defi-mooc-lab2 .`
4. Then run, `docker run -e ALCHE_API="https://eth-mainnet.alchemyapi.io/v2/HJ_i2RGc4L49NXkuwuST53fMYye2LGeB" -it defi-mooc-lab2 /bin/sh`
4. Open a second terminal, run `docker exec -it CONTAINER_ID /bin/bash`. You can get CONTAINER_ID by running `docker ps` in your first terminal
5. To run tests, go to your second terminal and run `npm test`
6. To copy files to your second terminal, run `docker cp path/to/file CONTAINER_ID:/destination/path`. ie `docker cp test/liquidation.js 46409c5f36f0:/lab2/test`

### Prerequisite

- You need to register an account on https://www.alchemy.com/ for access to an archive Ethereum node.

- You need to prepare the nodeJS environment for the project yourself, or have [docker](https://www.docker.com/) installed on your machine.

### Requirements

- The smart contract should allow you to perform a flash loan, a liquidation, and an asset exchange in one blockchain transaction.

- To ease marking, we require your contract to provide a unified interface `operate`. By calling `operate`, the flash loan, liquidation, and exchange should be executed properly. You are allowed to "hardcode" the execution logic and parameters in the `operate` function.

```javascript
function operate() external;
```

### Test case

You are expected to liquidate `0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F` on Aave V2 which was liquidated at block `12489620`. Check out the [original liquidation transaction](https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077).

### Commands

To test your contract:

1. `docker build -t defi-mooc-lab2 .`
2. `docker run -e ALCHE_API="$YOUR ALCHEMY ETHEREUM MAINNET API" -it defi-mooc-lab2 npm test`

## Background

We provide the following background information for this exercise.

### Aave liquidation

To trigger a liquidation on Aave, you need to call a public function `liquidationCall` provided by the Aave smart contracts. In the function, you can specify `user` representing the borrowing position you would like to liquidate, `debtAsset`, the cryptocurrency you would like to repay (let's say token D), and `collateralAsset`, the collateral cryptocurrency you would like claim from the borrowing position (let's say token C). You also specify the amount of debt you want to repay, `debtToCover`.

```javascript
function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address user,
    uint256 debtToCover,
    bool receiveAToken
  ) external;
```

By calling this function, you then repay some amount of token D to Aave and in return, some token C is sent to your account.

You should make sure that the user is in a liquidatable state. Otherwise, the aave smart contract would revert your transaction and you would pay transaction fees for an unsuccessful liquidation.
