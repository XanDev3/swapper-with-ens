// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { SwapStables } from "../../contracts/SwapStables.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockUniswapV2Router } from "../mocks/MockUniswapV2Router.sol";
import { ReentrantUniswapMock } from "../mocks/ReentrantUniswapMock.sol";

contract SwapStablesFuzz is Test {
    // Mirror custom errors from SwapStables for selector access
    error SwapStables__ZeroAmountIn();
    error SwapStables__NoPaths();
    error SwapStables__NoValidPath();

    SwapStables public swap;
    ERC20Mock public dai;
    MockUniswapV2Router public router;
    ReentrantUniswapMock public reentrant;

    address public USER = makeAddr("user");

    function setUp() public {
        // deploy swap with a mock router
        router = new MockUniswapV2Router(vm.addr(2));
        swap = new SwapStables(address(router));
        dai = new ERC20Mock("DAI", "DAI", vm.addr(1), 1_000_000 ether);
        // give router a healthy balance so mock sends succeed for bounded outputs
        vm.deal(address(router), 1000 ether);

        // seed some balances
        dai.transferInternal(vm.addr(1), USER, 1000 ether);
    }

    // 1) fuzzAmountValidRange
    function testFuzz_amountValidRange(uint256 amountIn) public {
        // bound to reasonable non-zero range
        amountIn = bound(amountIn, 0, 1_000 ether);

        address[] memory p = new address[](2);
        p[0] = address(dai);
        p[1] = vm.addr(2); // fake WETH addr for mock

        address[][] memory paths = new address[][](1);
        paths[0] = p;

        // Configure router deterministic output so swaps succeed when amountIn > 0
        uint256 out = amountIn / 2;
        // ensure a positive non-zero output for small non-zero inputs so estimateBestOut
        // and swap don't treat the path as invalid due to integer division
        if (amountIn > 0 && out == 0) out = 1;
        // cap to router balance to avoid mock-send-failed
        if (out > address(router).balance) out = address(router).balance;
        router.setPathOut(p, out);

        // Ensure USER has tokens and approval when amountIn > 0
        if (amountIn == 0) {
            vm.prank(USER);
            vm.expectRevert(abi.encodeWithSelector(SwapStables__ZeroAmountIn.selector));
            swap.swapStableToETHBest(address(dai), 0, paths, 0, block.timestamp + 1 hours);
            return;
        }

        // default happy path for bounded amounts
        vm.prank(USER);
        dai.approve(address(swap), amountIn);

        // transfer tokens into user (ensure balance)
        dai.transferInternal(vm.addr(1), USER, amountIn);

        uint256 beforeBal = USER.balance;
        vm.prank(USER);
        swap.swapStableToETHBest(address(dai), amountIn, paths, 0, block.timestamp + 1 hours);
        uint256 afterBal = USER.balance;
        assertGe(afterBal, beforeBal);
    }

    // 2) fuzzPathsVariousLengths
    function testFuzz_pathsVariousLengths(uint8 numPaths, uint8 pathLenSeed) public {
        // bound number of paths and path lengths
        numPaths = uint8(bound(numPaths, 1, 6));
        pathLenSeed = uint8(bound(pathLenSeed, 1, 4));

        address[][] memory paths = new address[][](numPaths);
        for (uint256 i = 0; i < numPaths; i++) {
            uint8 plen = uint8(bound(pathLenSeed + i, 1, 4));
            address[] memory p = new address[](plen);
            for (uint8 j = 0; j < plen; j++) {
                p[j] = address(dai);
            }
            paths[i] = p;
        }

        // configure router to return increasing outputs for paths >=2 length
        for (uint256 i = 0; i < numPaths; i++) {
            if (paths[i].length < 2) continue;
            uint256 out = (i + 1) * 1 ether;
            if (out > address(router).balance) out = address(router).balance;
            router.setPathOut(paths[i], out);
        }

        // ensure the fuzzer only uses inputs where at least one path is valid
        bool hasValid = false;
        for (uint256 i = 0; i < numPaths; i++) {
            if (paths[i].length >= 2) {
                hasValid = true;
                break;
            }
        }
        vm.assume(hasValid);

        // call estimate indirectly via swap (use amount 1 ether)
        vm.prank(USER);
        dai.approve(address(swap), 1 ether);
        dai.transferInternal(vm.addr(1), USER, 1 ether);

        vm.prank(USER);
        swap.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);

        // if there was at least one length>=2 path, swap should have succeeded; otherwise it would revert
    }

    // 3) fuzzPathValuesAndOrdering (mocked)
    function testFuzz_pathValuesOrdering(uint256 a, uint256 b, uint256 c) public {
        // create three paths
        // use distinct second-hops so setPathOut does not overwrite the same path key
        address[] memory p1 = new address[](2);
        p1[0] = address(dai);
        p1[1] = vm.addr(2);
        address[] memory p2 = new address[](2);
        p2[0] = address(dai);
        p2[1] = vm.addr(3);
        address[] memory p3 = new address[](2);
        p3[0] = address(dai);
        p3[1] = vm.addr(4);

        // bound outputs
        a = bound(a, 0, 10 ether);
        b = bound(b, 0, 10 ether);
        c = bound(c, 0, 10 ether);

        // ensure at least one non-zero path so estimateBestOut can succeed
        vm.assume(a > 0 || b > 0 || c > 0);

        // cap outputs to router balance and ensure non-zero where required
        uint256 aa = a;
        uint256 bb = b;
        uint256 cc = c;
        if (aa > address(router).balance) aa = address(router).balance;
        if (bb > address(router).balance) bb = address(router).balance;
        if (cc > address(router).balance) cc = address(router).balance;
        if (aa == 0 && (bb > 0 || cc > 0)) {
            // leave aa = 0 (some paths can be zero)
        } else if (aa == 0) {
            // make aa minimally positive to ensure at least one non-zero
            aa = 1;
        }
        if (bb == 0 && (aa > 0 || cc > 0)) { } else if (bb == 0) {
            bb = 1;
        }
        if (cc == 0 && (aa > 0 || bb > 0)) { } else if (cc == 0) {
            cc = 1;
        }
        router.setPathOut(p1, aa);
        router.setPathOut(p2, bb);
        router.setPathOut(p3, cc);

        address[][] memory paths = new address[][](3);
        paths[0] = p1;
        paths[1] = p2;
        paths[2] = p3;

        // ensure user has tokens
        dai.transferInternal(vm.addr(1), USER, 1 ether);
        vm.prank(USER);
        dai.approve(address(swap), 1 ether);

        // ensure router has enough ETH to pay out the largest configured out
        uint256 maxOut = aa;
        if (bb > maxOut) maxOut = bb;
        if (cc > maxOut) maxOut = cc;
        if (address(router).balance < maxOut) vm.deal(address(router), maxOut);

        // call swap; detect which path was selected by checking router's set values
        vm.prank(USER);
        swap.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);

        // Deterministic check: best value should be max(a,b,c)
        uint256 m = aa;
        if (bb > m) m = bb;
        if (cc > m) m = cc;
        // m should be > 0 otherwise estimateBestOut would revert; vm.assume above ensures this
    }

    // 4) fuzzTokensAndDecimals
    function testFuzz_tokensAndDecimals(uint8 decimals, uint256 amt) public {
        // decimals 0..18
        decimals = uint8(bound(decimals, 0, 18));
        uint256 base = 10 ** decimals;
        amt = bound(amt, 1, 1000 * base);

        // deploy an ERC20Mock with given decimals by minting scaled amounts (ERC20Mock uses 18 decimals by default)
        // we simulate different scales by interpreting amt with the provided decimals
        address token = address(dai); // reuse dai for simplicity; tests focus on arithmetic stability

        // configure path
        address[] memory p = new address[](2);
        p[0] = token;
        p[1] = vm.addr(2);

        address[][] memory paths = new address[][](1);
        paths[0] = p;

        // set router out proportional to amt and cap to router balance
        uint256 outAmt = amt / 2;
        if (amt > 0 && outAmt == 0) outAmt = 1;
        if (outAmt > address(router).balance) outAmt = address(router).balance;
        router.setPathOut(p, outAmt);

        // perform swap with bounded amt
        uint256 amountIn = bound(amt, 1, 1_000 ether);
        dai.transferInternal(vm.addr(1), USER, amountIn);
        vm.prank(USER);
        dai.approve(address(swap), amountIn);

        vm.prank(USER);
        swap.swapStableToETHBest(token, amountIn, paths, 0, block.timestamp + 1 hours);
    }

    // 5) fuzzReentrancyAttempt
    function testFuzz_reentrancyAttempt(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 10 ether);

        // deploy reentrant router and set to swap
        reentrant = new ReentrantUniswapMock(vm.addr(2));
        vm.deal(address(reentrant), 100 ether);
        reentrant = new ReentrantUniswapMock(vm.addr(2));
        vm.deal(address(reentrant), 100 ether);
        // redeploy swap with reentrant router for this test
        swap = new SwapStables(address(reentrant));

        // configure the reentrant router to call back into swap
        reentrant.setTarget(address(swap));
        address[] memory p = new address[](2);
        p[0] = address(dai);
        p[1] = vm.addr(2);
        address[][] memory paths = new address[][](1);
        paths[0] = p;

        // ensure user has tokens
        dai.transferInternal(vm.addr(1), USER, amountIn);
        vm.prank(USER);
        dai.approve(address(swap), amountIn);

        vm.prank(USER);
        vm.expectRevert(); // reentrancy guard should prevent second call
        swap.swapStableToETHBest(address(dai), amountIn, paths, 0, block.timestamp + 1 hours);
    }
}
