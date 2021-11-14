const { expect } = require("chai");
const { network, ethers } = require("hardhat");
const { BigNumber, utils }  = require("ethers");
const { writeFile } = require('fs');

let beforeLiquidationBalance;
let liquidationOperator;

let gasPrice;
let accounts;
let liquidator;

describe("Liquidation", function () {
  it("test", async function () {
    await network.provider.request({
        method: "hardhat_reset",
        params: [{
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/HJ_i2RGc4L49NXkuwuST53fMYye2LGeB`,
            blockNumber: 12489619,
          }
        }]
      });
  });

  it("Setup contracts", async function (){
    gasPrice = 0;

    accounts = await ethers.getSigners();
    liquidator = accounts[0].address;

    beforeLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const LiquidationOperator = await ethers.getContractFactory("LiquidationOperator");
    liquidationOperator = await LiquidationOperator.deploy(overrides = {gasPrice: gasPrice});
    await liquidationOperator.deployed();

  });
  
  it("Liquidate Transaction", async function(){
    const liquidationTx = await liquidationOperator.operate(overrides = {gasPrice: gasPrice});
    const liquidationReceipt = await liquidationTx.wait();

    const liquidationEvents = liquidationReceipt.logs.filter(
        v => v && v.topics && v.address === '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9' && Array.isArray(v.topics) && 
        v.topics.length > 3 && v.topics[0] === '0xe413a321e8681d831f4dbccbca790d2952b56f977908e45be37335533e005286')

    const expectedLiquidationEvents = liquidationReceipt.logs.filter(v => v.topics[3] === '0x00000000000000000000000059ce4a2ac5bc3f5f225439b2993b86b42f6d3e9f');

    expect(expectedLiquidationEvents.length, "no expected liquidation").to.be.above(0);
    expect(liquidationEvents.length, "unexpected liquidation").to.be.equal(expectedLiquidationEvents.length);

    const afterLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const profit = afterLiquidationBalance.sub(beforeLiquidationBalance);
    console.log("Profit", utils.formatEther(profit), "ETH");

    expect(profit.gt(BigNumber.from(0)), "not profitable").to.be.true;
    writeFile('profit.txt', String(utils.formatEther(profit)), function (err) {console.log("failed to write profit.txt: %s", err)});

  });
});
