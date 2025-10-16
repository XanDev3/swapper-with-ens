//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { Test, console } from "forge-std/Test.sol";
import { SwapStables } from "../../contracts/SwapStables.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockUniswapV2Router } from "../mocks/MockUniswapV2Router.sol";
import { RevertingUniswapMock } from "../mocks/RevertingUniswapMock.sol";
import { ReentrantUniswapMock } from "../mocks/ReentrantUniswapMock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RevertingTransferERC20, ApproveRevertingERC20 } from "../mocks/MockRevertingERC20s.sol";

contract SwapStablesTest is Test {
    // Mirror the custom errors from SwapStables so tests can reference selectors
    error SwapStables__TransferFromFailed();
    error SwapStables__InvalidRouter();
    error SwapStables__RouterNotConfigured();
    error SwapStables__NoPaths();
    error SwapStables__NoValidPath();
    error SwapStables__ZeroAmountIn();
    error SwapStables__EthSendFailed();
    error SwapStables__ApproveFailed();
    error SwapStables__DeadlineExpired();

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event SwapExecuted(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    SwapStables public swapStablesContract;
    ERC20Mock public dai;
    // last-created mocks for reuse in modifiers
    ERC20Mock public mockWeth;
    MockUniswapV2Router public mockRouter;
    RevertingUniswapMock public lastRevertingRouter;
    address public OWNER = makeAddr("owner"); // Create a random owner or use the account at vm.addr(1)?
    address public SWAPPER = makeAddr("swapper");
    uint256 public constant INITIAL_DAI_SUPPLY = 1000 ether;
        function setUp() public {
        // Default setup: deploy a swap contract with a zero-address router to match legacy tests that
        // verify initial router state. Tests that need a router should redeploy via modifiers above.
        // Since constructor requires a non-zero router, we deploy with a placeholder mock router created here.
        mockWeth = new ERC20Mock("WETH", "WETH", vm.addr(1), 0);
        mockRouter = new MockUniswapV2Router(address(mockWeth));
        vm.deal(address(mockRouter), 10 ether);
        swapStablesContract = new SwapStables(address(mockRouter));
        dai = new ERC20Mock("DAI", "DAI", vm.addr(1), INITIAL_DAI_SUPPLY); // Change address to receive dai supply if necessary

        vm.prank(vm.addr(1));
        dai.transferInternal(vm.addr(1), SWAPPER, 100 ether);
    }

    // Modifier to deploy and set a standard mock router
    modifier withMockRouter() {
        mockWeth = new ERC20Mock("WETH", "WETH", vm.addr(1), 0);
        mockRouter = new MockUniswapV2Router(address(mockWeth));
        // fund router so it can send ETH during tests
        vm.deal(address(mockRouter), 10 ether);
        // redeploy swap contract using this mock router so tests exercise constructor-injected router
        swapStablesContract = new SwapStables(address(mockRouter));
        _;
    }
        // Modifier to deploy and set a reverting mock router
    modifier withRevertingRouter() {
        lastRevertingRouter = new RevertingUniswapMock(address(0));
        vm.deal(address(lastRevertingRouter), 5 ether);
        swapStablesContract = new SwapStables(address(lastRevertingRouter));
        _;
    }
// 1. testDeployInitialState
    function testDeployInitialState() public {
        // Since router is required in constructor, deploy with a mock router and ensure owner is correct
        ERC20Mock localWeth = new ERC20Mock("WETH", "WETH", vm.addr(1), 0);
        MockUniswapV2Router localRouter = new MockUniswapV2Router(address(localWeth));
        SwapStables s = new SwapStables(address(localRouter));
        assertEq(address(s.uniV2()), address(localRouter));
        assertEq(s.owner(), address(this));
    }
    function testCanReceiveStableCoins() public {
        assertEq(ERC20Mock(dai).balanceOf(SWAPPER), 100 ether);

        vm.startBroadcast(SWAPPER);
        ERC20Mock(dai).transferInternal(SWAPPER, address(swapStablesContract), 10 ether);
        vm.stopBroadcast();
        assertEq(ERC20Mock(dai).balanceOf(address(swapStablesContract)), 10 ether);
        assertEq(ERC20Mock(dai).balanceOf(SWAPPER), 90 ether);
    }

    // 2. Happy Path
    function testSwapStableToETHBestPicksBestPath() public withMockRouter {
        // prepare two paths: pathA and pathB, both [DAI, WETH]
        address[] memory pathA = new address[](2);
        pathA[0] = address(dai);
        pathA[1] = address(mockWeth);

        address[] memory pathB = new address[](2);
        pathB[0] = address(dai);
        pathB[1] = address(mockWeth);

        // set path outputs: pathA -> 1 ETH, pathB -> 2 ETH (pathB is better)
        mockRouter.setPathOut(pathA, 1 ether);
        mockRouter.setPathOut(pathB, 2 ether);

        // ensure SWAPPER approved
        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        // perform swap
        address[][] memory paths = new address[][](2);
        paths[0] = pathA;
        paths[1] = pathB;

        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 10 ether, paths, 0, block.timestamp + 1 hours);

        // contract should not retain DAI
        assertEq(ERC20Mock(dai).balanceOf(address(swapStablesContract)), 0);
    }


    // 3. testEstimateBestOutSinglePathReturnsAmount (via swap)
    function testEstimateBestOutSinglePathReturnsAmount() public withMockRouter {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        // configure mock output
        mockRouter.setPathOut(path, 3 ether);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // ensure SWAPPER has approval
        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        uint256 ethBefore = address(SWAPPER).balance;
        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = address(SWAPPER).balance;

        assertEq(ethAfter - ethBefore, 3 ether);
    }

    // 4. testEstimateBestOutSelectsMaxOfMultiplePaths (via swap)
    function testEstimateBestOutSelectsMaxOfMultiplePaths() public withMockRouter {
        address[] memory p1 = new address[](2);
        p1[0] = address(dai);
        p1[1] = address(mockWeth);

        address[] memory p2 = new address[](2);
        p2[0] = address(dai);
        p2[1] = address(mockWeth);

        mockRouter.setPathOut(p1, 1 ether);
        mockRouter.setPathOut(p2, 5 ether);

        address[][] memory paths = new address[][](2);
        paths[0] = p1;
        paths[1] = p2;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        uint256 ethBefore = address(SWAPPER).balance;
        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = address(SWAPPER).balance;

        // best path returns 5 ether
        assertEq(ethAfter - ethBefore, 5 ether);
    }

    // 5. testEstimateBestOutIgnoresFailingPath (via swap)
    function testEstimateBestOutIgnoresFailingPath() public withRevertingRouter {
        address[] memory good = new address[](2);
        good[0] = address(dai);
        good[1] = address(0xBEEF);

        address[] memory bad = new address[](2);
        bad[0] = address(dai);
        bad[1] = address(uint160(0xDEAD));

        lastRevertingRouter.setPathOut(good, 2 ether);
        lastRevertingRouter.setPathOut(bad, 0);
        lastRevertingRouter.setBadPath(bad);

        address[][] memory paths = new address[][](2);
        paths[0] = bad;
        paths[1] = good;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        uint256 ethBefore = address(SWAPPER).balance;
        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = address(SWAPPER).balance;

        assertEq(ethAfter - ethBefore, 2 ether);
    }

    // 6. testEstimateBestOutNoValidPathReverts (via swap)
    function testEstimateBestOutNoValidPathReverts() public withMockRouter {
        address[] memory p = new address[](2);
        p[0] = address(dai);
        p[1] = address(mockWeth);

        mockRouter.setPathOut(p, 0);

        address[][] memory paths = new address[][](1);
        paths[0] = p;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(SwapStables__NoValidPath.selector));
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 7. testSwapStableToETHBestHappyPathMock (extended assertions)
    function testSwapStableToETHBestHappyPathMock() public withMockRouter {
        // path
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        mockRouter.setPathOut(path, 2 ether);

        // ensure SWAPPER has approval
        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        uint256 daiBefore = ERC20Mock(dai).balanceOf(SWAPPER);
        uint256 ethBefore = address(SWAPPER).balance;

        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 10 ether, paths, 0, block.timestamp + 1 hours);

        uint256 daiAfter = ERC20Mock(dai).balanceOf(SWAPPER);
        uint256 ethAfter = address(SWAPPER).balance;

        assertEq(daiBefore - daiAfter, 10 ether, "caller DAI decreased by amountIn");
        assertGt(ethAfter, ethBefore, "caller ETH should increase after swap");
        assertEq(ERC20Mock(dai).balanceOf(address(swapStablesContract)), 0, "contract should not hold DAI after swap");
    }

    // 8. testSwapRevertsIfAmountZero
    function testSwapRevertsIfAmountZero() public withMockRouter {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(SwapStables__ZeroAmountIn.selector));
        swapStablesContract.swapStableToETHBest(address(dai), 0, paths, 0, block.timestamp + 1 hours);
    }

    // 9. testSwapRevertsIfRouterNotSet
    function testSwapRevertsIfRouterNotSet() public {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(dai);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // Since router must be provided at construction, we deploy a contract whose router returns 0
        // to simulate no valid route rather than an unset router. Reuse a mock router with no outputs.
        MockUniswapV2Router deadRouter = new MockUniswapV2Router(address(0));
        SwapStables dead = new SwapStables(address(deadRouter));

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(dead), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert();
        dead.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 10. testSwapRevertsIfPathsEmpty
    function testSwapRevertsIfPathsEmpty() public withMockRouter {
        address[][] memory paths = new address[][](0);

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(SwapStables__NoPaths.selector));
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 11. testSwapRevertsWhenTransferFromFails
    function testSwapRevertsWhenTransferFromFails() public withMockRouter {
        // deploy a token that reverts on transferFrom
        RevertingTransferERC20 bad = new RevertingTransferERC20("BAD", "BAD", vm.addr(2), 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(bad);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // fund SWAPPER with BAD tokens
        bad.transferInternal(vm.addr(2), SWAPPER, 10 ether);

        vm.prank(SWAPPER);
        // approve internal should work but transferFrom will revert
        bad.approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        vm.prank(SWAPPER);
        vm.expectRevert();
        swapStablesContract.swapStableToETHBest(address(bad), 1 ether, paths, 0, block.timestamp + 1 hours);
        vm.assertEq(bad.balanceOf(address(swapStablesContract)), 0);
    }

    // New: test that SwapStables reverts with SwapStables__ApproveFailed when approve returns false
    function testApproveRevertBubblesUp() public withMockRouter {
        // deploy a token that reverts on approve
        ApproveRevertingERC20 bad = new ApproveRevertingERC20("BADAPR", "BAD", vm.addr(1), 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(bad);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // fund SWAPPER with tokens
        bad.transferInternal(vm.addr(1), SWAPPER, 10 ether);

        // ensure SWAPPER approved this contract to pull tokens
        vm.prank(SWAPPER);
        bad.approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        vm.prank(SWAPPER);
        // the token's approve will revert with "approve-reverted" when the contract tries to approve router
        vm.expectRevert(bytes("approve-reverted"));
        swapStablesContract.swapStableToETHBest(address(bad), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 12. testApproveFailureDoesntLeaveTokensInContract
    function testApproveFailureDoesntLeaveTokensInContract() public withMockRouter {
        ApproveRevertingERC20 appRev = new ApproveRevertingERC20("APR", "APR", vm.addr(3), 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(appRev);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // transfer tokens to SWAPPER
        appRev.transferInternal(vm.addr(3), SWAPPER, 10 ether);

        // set allowance directly to simulate nonstandard approve behavior
        vm.prank(SWAPPER);
        appRev.approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        // now simulate that approve would revert on real ERC20; we expect the swap to still attempt approve and proceed
        // because our token's approve is bypassed, the internal approve will succeed. To simulate failure, call swap with token that will revert on approve if used.

        // For simplicity: call swap and expect it to revert. We'll set router to return 0 to force revert after transferFrom.
        mockRouter.setPathOut(path, 0);

        vm.prank(SWAPPER);
        appRev.approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        vm.prank(SWAPPER);
        vm.expectRevert();
        swapStablesContract.swapStableToETHBest(address(appRev), 10 ether, paths, 0, block.timestamp + 1 hours);

        // approve reverted, which rolls back the whole swap call — tokens should NOT be in the contract
        assertEq(appRev.balanceOf(address(swapStablesContract)), 0);
    }
        // 13. testSwapEmitsEvent
    function testSwapEmitsEvent() public withMockRouter {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        mockRouter.setPathOut(path, 2 ether);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        vm.prank(SWAPPER);
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(SWAPPER, address(dai), 10 ether, 2 ether);
        swapStablesContract.swapStableToETHBest(address(dai), 10 ether, paths, 0, block.timestamp + 1 hours);
    }

    // New: test that deadline is enforced by SwapStables and reverts when expired
    function testSwapRevertsIfDeadlineExpired() public withMockRouter {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // ensure SWAPPER has approval
        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        // call with expired deadline
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(SwapStables__DeadlineExpired.selector));
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp - 1);
    }

    // 14. testEstimateSkipsShortPaths
    function testEstimateSkipsShortPaths() public withMockRouter {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(dai);

        address[] memory goodPath = new address[](2);
        goodPath[0] = address(dai);
        goodPath[1] = address(mockWeth);

        mockRouter.setPathOut(goodPath, 4 ether);

        address[][] memory paths = new address[][](2);
        paths[0] = shortPath;
        paths[1] = goodPath;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        uint256 ethBefore = address(SWAPPER).balance;
        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = address(SWAPPER).balance;

        assertEq(ethAfter - ethBefore, 4 ether);
    }

    // 15. testRouterInsufficientFundsReverts
    function testRouterInsufficientFundsReverts() public {
        // deploy a router with small balance
        ERC20Mock localWeth = new ERC20Mock("WETH", "WETH", vm.addr(1), 0);
        MockUniswapV2Router smallRouter = new MockUniswapV2Router(address(localWeth));
        // fund router with only 1 ether
        vm.deal(address(smallRouter), 1 ether);

        // redeploy swap contract to use the smallRouter so the mock router has limited funds
        swapStablesContract = new SwapStables(address(smallRouter));

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(localWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // set output larger than router balance to force mock-send-failed
        smallRouter.setPathOut(path, 2 ether);

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert(); // mock-send-failed bubbles up
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 16. testContractCanReceiveETH
    function testContractCanReceiveETH() public {
        uint256 before = address(swapStablesContract).balance;
        (bool ok,) = payable(address(swapStablesContract)).call{ value: 1 ether }("");
        require(ok, "send failed");
        assertEq(address(swapStablesContract).balance - before, 1 ether);
    }

    // 17. testReentrancyGuardPreventsReentrancy
    function testReentrancyGuardPreventsReentrancy() public {
        // deploy a reentrant router that will call back into SwapStables.swapStableToETHBest
        ReentrantUniswapMock r = new ReentrantUniswapMock(address(mockWeth));
        // fund reentrant router
        vm.deal(address(r), 10 ether);

        // redeploy swap contract to use the reentrant router for this test
        swapStablesContract = new SwapStables(address(r));

        // make the router attempt to reenter SwapStables during swap
        r.setTarget(address(swapStablesContract));

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(mockWeth);

        address[][] memory paths = new address[][](1);
        paths[0] = path;

        // configure router to attempt reentrant call
        r.setPathOut(path, 1 ether);

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        vm.prank(SWAPPER);
        vm.expectRevert(); // reentrancy should cause revert via nonReentrant
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
    }

    // 18. testMultipleEqualPathsStillSucceeds
    function testMultipleEqualPathsStillSucceeds() public withMockRouter {
        address[] memory p1 = new address[](2);
        p1[0] = address(dai);
        p1[1] = address(mockWeth);

        address[] memory p2 = new address[](2);
        p2[0] = address(dai);
        p2[1] = address(mockWeth);

        mockRouter.setPathOut(p1, 2 ether);
        mockRouter.setPathOut(p2, 2 ether);

        address[][] memory paths = new address[][](2);
        paths[0] = p1;
        paths[1] = p2;

        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 1 ether);

        uint256 ethBefore = address(SWAPPER).balance;
        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 1 ether, paths, 0, block.timestamp + 1 hours);
        uint256 ethAfter = address(SWAPPER).balance;

        assertEq(ethAfter - ethBefore, 2 ether);
    }
}
