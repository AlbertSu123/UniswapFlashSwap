//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external returns (bool);
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the WETHUSDT_pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address WETHUSDT_pair);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/WETHUSDT_pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the WETHUSDT_pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    //I added these two functions
    function token0() external returns (address);

    function token1() external returns (address);
}

// ----------------------IMPLEMENTATION------------------------------

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    //    *** Your code here ***
    // END TODO
    ILendingPool lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address liquidateThisGuy_address =
        0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    address USDT_address = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address WBTC_address = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address UniswapV2Factory_address =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address WETH_address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address WETHUSDT_pair = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    uint256 USDT_borrow_amount = 2916378221684; //Decimals = 6

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    constructor() {
        // TODO: (optional) initialize your contract
        //   *** Your code here ***
        // END TODO
    }

    receive() external payable {}

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // TODO: implement your liquidation logic

        // 0. security checks and initializing variables
        //    *** Your code here ***

        // 1. get the target user account data & make sure it is liquidatable
        //    *** Your code here ***
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = lendingPool.getUserAccountData(liquidateThisGuy_address);

        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***
        bytes memory data = abi.encode(
            address(this),
            USDT_address,
            WBTC_address
        );
        uint256 amount0 = IUniswapV2Pair(WETHUSDT_pair).token0() == USDT_address
            ? USDT_borrow_amount
            : 0;
        uint256 amount1 = IUniswapV2Pair(WETHUSDT_pair).token1() == USDT_address
            ? USDT_borrow_amount
            : 0;
        IUniswapV2Pair(WETHUSDT_pair).swap(
            amount0,
            amount1,
            address(this),
            data
        );

        // 3. Convert the profit into ETH and send back to sender
        //    *** Your code here ***
        // END TODO
        uint256 WETH_balance = IERC20(WETH_address).balanceOf(address(this));
        IWETH(WETH_address).withdraw(WETH_balance);
        payable(msg.sender).transfer(WETH_balance);
    }

    // required by the swap
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        // TODO: implement your liquidation logic
        // 2.0. security checks and initializing variables
        //    *** Your code here ***

        // 2.1 liquidate the target user
        //    *** Your code here ***
        //Need to approve lending pool to take USDT
        address eth_usdt_uniswap = WETHUSDT_pair; // uniswap WETHUSDT_pair for ETH-USDT;
        // IERC20(USDT_address).approve(eth_usdt_uniswap, USDT_borrow_amount);
        IERC20(USDT_address).approve(address(lendingPool), USDT_borrow_amount);
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        (
            address collateralAsset,
            address debtAsset,
            address user,
            uint256 debtToCover,
            bool receiveAToken
        ) = (
                WBTC_address,
                USDT_address,
                liquidateThisGuy_address,
                USDT_borrow_amount,
                false
            );
        lendingPool.liquidationCall(
            collateralAsset,
            debtAsset,
            user,
            debtToCover,
            receiveAToken
        );

        // 2.2 swap WBTC for other things or repay directly
        //    *** Your code here ***
        //Need to get as much weth as possible by swapping the WBTC we got from liquidating the dude
        address wethWBTC_pair = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
        (
            uint112 WBTC_reserve,
            uint112 WETH_reserve,
            uint32 blockTimestampLast
        ) = IUniswapV2Pair(wethWBTC_pair).getReserves();
        uint256 WETH_Amount_Out = getAmountOut(
            IERC20(WBTC_address).balanceOf(address(this)),
            uint256(WBTC_reserve),
            uint256(WETH_reserve)
        );
        IERC20(WBTC_address).transfer(
            wethWBTC_pair,
            IERC20(WBTC_address).balanceOf(address(this))
        );
        IUniswapV2Pair(wethWBTC_pair).swap(
            0,
            WETH_Amount_Out,
            address(this),
            ""
        );

        // 2.3 repay
        //    *** Your code here ***
        //Need to repay USDTWETH

        (
            uint112 USDT_reserve_WETHUSDT,
            uint112 WETH_reserve_WETHUSDT,
            uint32 blockTimestampLast_WETHUSDT
        ) = IUniswapV2Pair(wethWBTC_pair).getReserves();
        console.log(USDT_reserve_WETHUSDT, WETH_reserve_WETHUSDT);
        uint256 WETH_amountIn = getAmountIn(
            USDT_borrow_amount,
            uint256(USDT_reserve_WETHUSDT),
            uint256(WETH_reserve_WETHUSDT)
        );
        console.log("WETH to repay", WETH_amountIn, USDT_borrow_amount);
        IERC20(WETH_address).transfer(
            WETHUSDT_pair,
            IERC20(WETH_address).balanceOf(address(this)) - 24 * 10**18
        );
        // END TODO
    }
}
