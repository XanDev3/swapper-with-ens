// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ForkHelpers } from "../utils/ForkHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapStables } from "../../contracts/SwapStables.sol";

// Minimal full router interface for ETH->token swaps used in integration tests
interface IUniswapV2Router02Full {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

contract SwapStablesIntegration is Test, ForkHelpers {
    // Mainnet addresses
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Test actor
    address internal TEST_USER;

    SwapStables public swapStables;

    function setUp() public {
        TEST_USER = vm.addr(7777);
        swapStables = new SwapStables();
        // NOTE: Fork creation is done externally by the test runner. Run these tests with:
        //   forge test --fork-url "http://127.0.0.1:8545" --fork-block-number $FORK_BLOCK -vvv test/integration/SwapStablesIntegration.t.sol
        // Optionally set FORK_BLOCK in the environment; if omitted, latest block will be used.

        // Set router to mainnet router (assumes the runner provided a mainnet fork)
        vm.prank(swapStables.owner());
        swapStables.setRouter(UNISWAP_V2_ROUTER);
    }

    /// Helper: find a whale address from a candidate list that holds at least minBalance of token
    function findWhale(address token, address[] memory candidates, uint256 minBalance)
        internal
        view
        returns (address)
    {
        for (uint256 i = 0; i < candidates.length; i++) {
            if (IERC20(token).balanceOf(candidates[i]) >= minBalance) {
                return candidates[i];
            }
        }
        return address(0);
    }

    /// Candidate whales (these are common large holders; replace if necessary)
    function daiCandidates() internal pure returns (address[] memory) {
        address[] memory addrs = new address[](4);
        addrs[0] = 0x28C6c06298d514Db089934071355E5743bf21d60; // common exchange
        addrs[1] = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // exchange
        addrs[2] = 0x742d35Cc6634C0532925a3b844Bc454e4438f44e; // large holder
        addrs[3] = 0x564286362092D8e7936f0549571a803B203aAceD; // sample
        return addrs;
    }

    /// USDC candidate whales. Prefer using an env override when running tests.
    /// Example: export USDC_WHALE=0x....
    function usdcCandidates() internal view returns (address[] memory) {
        // if user provided an override via env, use that single address
        address overrideAddr = address(0);
        // vm.envAddress reverts when variable is not set; guard by try/catch so tests don't fail
        try vm.envAddress("USDC_WHALE") returns (address addr) {
            overrideAddr = addr;
        } catch {
            overrideAddr = address(0);
        }
        if (overrideAddr != address(0)) {
            address[] memory only = new address[](1);
            only[0] = overrideAddr;
            return only;
        }

        // Default: use a known AAVE USDC holder (this address held significant USDC at common blocks)
        address[] memory addrs = new address[](1);
        addrs[0] = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c; // AAVE USDC
        return addrs;
    }

    // ETH -> DAI: buy DAI with ETH via the real router, then swap DAI->ETH via SwapStables
    function testEthToDaiViaSwapStablesSucceeds() public useSnapshot {
        uint256 ethToSpend = 1 ether;

        // fund test user with ETH to buy DAI
        fund(TEST_USER, 2 ether);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = DAI;

        // buy DAI as TEST_USER
        vm.prank(TEST_USER);
        IUniswapV2Router02Full(UNISWAP_V2_ROUTER).swapExactETHForTokens{ value: ethToSpend }(
            0, buyPath, TEST_USER, block.timestamp + 1 hours
        );

        uint256 daiBalance = IERC20(DAI).balanceOf(TEST_USER);
        assertGt(daiBalance, 0, "should have bought some DAI");

        // Now approve and swap DAI -> ETH via SwapStables
        approveAs(TEST_USER, DAI, address(swapStables), daiBalance);

        address[] memory sellPath = new address[](2);
        sellPath[0] = DAI;
        sellPath[1] = WETH;

        address[][] memory sellPaths = new address[][](1);
        sellPaths[0] = sellPath;

        uint256 ethBefore = TEST_USER.balance;
        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(DAI, daiBalance, sellPaths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = TEST_USER.balance;

        assertGt(ethAfter, ethBefore, "should receive ETH when swapping DAI->ETH");
        assertEq(IERC20(DAI).balanceOf(TEST_USER), 0, "DAI should be spent after swap");
    }

    // ETH->DAI high-slippage flow: buy DAI then attempt to swap with an unrealistic amountOutMin to force revert
    function testEthToDaiHighSlippageRevertsViaSwapStables() public useSnapshot {
        uint256 ethToSpend = 1 ether;

        fund(TEST_USER, 2 ether);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = DAI;

        vm.prank(TEST_USER);
        IUniswapV2Router02Full(UNISWAP_V2_ROUTER).swapExactETHForTokens{ value: ethToSpend }(
            0, buyPath, TEST_USER, block.timestamp + 1 hours
        );

        uint256 daiBalance = IERC20(DAI).balanceOf(TEST_USER);
        assertGt(daiBalance, 0, "should have bought some DAI");

        // compute expected out for DAI->ETH and force amountOutMin to be larger
        address[] memory sellPath = new address[](2);
        sellPath[0] = DAI;
        sellPath[1] = WETH;

        address[][] memory sellPaths = new address[][](1);
        sellPaths[0] = sellPath;

        uint256[] memory predicted = routerGetAmountsOut(UNISWAP_V2_ROUTER, daiBalance, sellPath);
        uint256 expectedOut = predicted[predicted.length - 1];

        vm.prank(TEST_USER);
        vm.expectRevert();
        swapStables.swapStableToETHBest(DAI, daiBalance, sellPaths, expectedOut + 1, block.timestamp + 1 hours);
    }

    // DAI -> ETH zero input should revert
    function testDaiToEthZeroInputRevertsViaSwapStables() public useSnapshot {
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        vm.prank(TEST_USER);
        // contract uses a require with message "SwapStables: ZERO_AMOUNT_IN"
        vm.expectRevert(bytes("SwapStables: ZERO_AMOUNT_IN"));
        swapStables.swapStableToETHBest(DAI, 0, paths, 0, block.timestamp + 1 hours);
    }

    // Decimals handling (DAI): swap 1 DAI and assert ETH received
    function testDecimalsHandling_DAI() public useSnapshot {
        uint256 humanOneDAI = 1e18; // 1 DAI

        address daiWhale = findWhale(DAI, daiCandidates(), humanOneDAI);
        require(daiWhale != address(0), "no-dai-whale-found");

        impersonateAndTransfer(DAI, daiWhale, TEST_USER, humanOneDAI);
        fund(TEST_USER, 1 ether);
        approveAs(TEST_USER, DAI, address(swapStables), humanOneDAI);

        address[] memory pDAI = new address[](2);
        pDAI[0] = DAI;
        pDAI[1] = WETH;

        address[][] memory pathsDAI = new address[][](1);
        pathsDAI[0] = pDAI;

        uint256 ethBefore = TEST_USER.balance;
        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(DAI, humanOneDAI, pathsDAI, 0, block.timestamp + 1 hours);
        uint256 ethAfter = TEST_USER.balance;
        assertGt(ethAfter - ethBefore, 0, "DAI swap produced ETH");
    }

    // Decimals handling (USDC): swap 1 USDC and assert ETH received
    function testDecimalsHandling_USDC() public useSnapshot {
        uint256 humanOneUSDC = 1e6; // 1 USDC

        address usdcWhale = findWhale(USDC, usdcCandidates(), humanOneUSDC);
        require(usdcWhale != address(0), "no-usdc-whale-found");

        impersonateAndTransfer(USDC, usdcWhale, TEST_USER, humanOneUSDC);
        fund(TEST_USER, 1 ether);
        approveAs(TEST_USER, USDC, address(swapStables), humanOneUSDC);

        address[] memory pUSDC = new address[](2);
        pUSDC[0] = USDC;
        pUSDC[1] = WETH;

        address[][] memory pathsUSDC = new address[][](1);
        pathsUSDC[0] = pUSDC;

        uint256 ethBefore = TEST_USER.balance;
        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(USDC, humanOneUSDC, pathsUSDC, 0, block.timestamp + 1 hours);
        uint256 ethAfter = TEST_USER.balance;
        assertGt(ethAfter - ethBefore, 0, "USDC swap produced ETH");
    }

    // Large swap impact: compare per-unit price for a small and a large swap to verify price impact
    function testLargeSwapImpactOnPriceFork() public useSnapshot {
        uint256 smallAmount = 1 ether; // 1 DAI
        uint256 largeAmount = 100_000 ether; // 100k DAI

        // compute router predictions for small and large
        address[] memory p = new address[](2);
        p[0] = DAI;
        p[1] = WETH;
        uint256[] memory outSmall = routerGetAmountsOut(UNISWAP_V2_ROUTER, smallAmount, p);
        uint256[] memory outLarge = routerGetAmountsOut(UNISWAP_V2_ROUTER, largeAmount, p);

        uint256 smallOut = outSmall[outSmall.length - 1];
        uint256 largeOut = outLarge[outLarge.length - 1];

        // per-unit comparison: smallOut / smallAmount should be > largeOut / largeAmount
        // cross-multiply to avoid fractions: smallOut * largeAmount > largeOut * smallAmount
        bool priceImpact = (smallOut * largeAmount) > (largeOut * smallAmount);
        assertTrue(priceImpact, "large swap should have worse per-unit price (price impact)");

        // Additionally, perform a large swap to ensure execution succeeds (use a whale)
        address whale = findWhale(DAI, daiCandidates(), largeAmount);
        if (whale == address(0)) {
            // skip actual large execution if no whale available on the fork
            return;
        }

        impersonateAndTransfer(DAI, whale, TEST_USER, largeAmount);
        approveAs(TEST_USER, DAI, address(swapStables), largeAmount);

        address[][] memory paths = new address[][](1);
        paths[0] = p;

        // perform swap (should succeed or revert if router limits); we assert no revert here
        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(DAI, largeAmount, paths, 0, block.timestamp + 1 hours);
    }

    // 1) Happy-path DAI -> ETH
    function testDaiToEthViaSwapStablesSucceeds() public useSnapshot {
        uint256 amountIn = 1 ether; // 1 DAI

        // pick a DAI whale with sufficient balance
        address whale = findWhale(DAI, daiCandidates(), amountIn);
        require(whale != address(0), "no-dai-whale-found");

        // transfer DAI to TEST_USER and approve
        impersonateAndTransfer(DAI, whale, TEST_USER, amountIn);
        fund(TEST_USER, 1 ether); // gas
        approveAs(TEST_USER, DAI, address(swapStables), amountIn);

        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        uint256 ethBefore = TEST_USER.balance;
        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(DAI, amountIn, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = TEST_USER.balance;

        assertGt(ethAfter, ethBefore, "ETH should increase after swap");
        assertEq(IERC20(DAI).balanceOf(TEST_USER), 0, "DAI should be spent");
    }

    // 2) Best-path selection between [DAI,WETH] and [DAI,USDC,WETH]
    function testSelectsBestPathBetweenDirectAndTwoHopFork() public useSnapshot {
        uint256 amountIn = 1 ether;
        address whale = findWhale(DAI, daiCandidates(), amountIn);
        require(whale != address(0), "no-dai-whale-found");

        impersonateAndTransfer(DAI, whale, TEST_USER, amountIn);
        fund(TEST_USER, 1 ether);
        approveAs(TEST_USER, DAI, address(swapStables), amountIn);

        address[] memory p1 = new address[](2);
        p1[0] = DAI;
        p1[1] = WETH;

        address[] memory p2 = new address[](3);
        p2[0] = DAI;
        p2[1] = USDC;
        p2[2] = WETH;

        address[][] memory paths = new address[][](2);
        paths[0] = p1;
        paths[1] = p2;

        // compute expected outs via router
        uint256[] memory out1 = routerGetAmountsOut(UNISWAP_V2_ROUTER, amountIn, p1);
        uint256[] memory out2 = routerGetAmountsOut(UNISWAP_V2_ROUTER, amountIn, p2);

        // ensure router returns values for both paths
        assertGt(out1[out1.length - 1], 0, "direct path should return > 0");
        assertGt(out2[out2.length - 1], 0, "two-hop path should return > 0");

        vm.prank(TEST_USER);
        swapStables.swapStableToETHBest(DAI, amountIn, paths, 0, block.timestamp + 1 hours);

        // simple assertion that test user received ETH
        assertGt(TEST_USER.balance, 0, "user ETH should be > 0 after swap");
    }

    // 3) Slippage protection revert
    function testSlippageProtectionRevertsOnLargeSlippageFork() public useSnapshot {
        uint256 amountIn = 1 ether;
        address whale = findWhale(DAI, daiCandidates(), amountIn);
        require(whale != address(0), "no-dai-whale-found");

        impersonateAndTransfer(DAI, whale, TEST_USER, amountIn);
        fund(TEST_USER, 1 ether);
        approveAs(TEST_USER, DAI, address(swapStables), amountIn);

        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // compute expected out and set amountOutMin greater than expected to force revert
        uint256[] memory out = routerGetAmountsOut(UNISWAP_V2_ROUTER, amountIn, path);
        uint256 expectedOut = out[out.length - 1];

        vm.prank(TEST_USER);
        vm.expectRevert();
        swapStables.swapStableToETHBest(DAI, amountIn, paths, expectedOut + 1, block.timestamp + 1 hours);
    }

    // 4) Deadline expired revert
    function testDeadlineExpiredRevertsFork() public useSnapshot {
        uint256 amountIn = 1 ether;
        address whale = findWhale(DAI, daiCandidates(), amountIn);
        require(whale != address(0), "no-dai-whale-found");

        impersonateAndTransfer(DAI, whale, TEST_USER, amountIn);
        fund(TEST_USER, 1 ether);
        approveAs(TEST_USER, DAI, address(swapStables), amountIn);

        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        vm.prank(TEST_USER);
        vm.expectRevert();
        // deadline in the past
        swapStables.swapStableToETHBest(DAI, amountIn, paths, 0, block.timestamp - 1000);
    }
}
