//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { Test, console } from "forge-std/Test.sol";
import { SwapStables } from "../contracts/SwapStables.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { MockUniswapV2Router } from "./mocks/MockUniswapV2Router.sol";

contract SwapStablesTest is Test {
    SwapStables public swapStablesContract;
    ERC20Mock public dai;
    address public OWNER = makeAddr("owner"); // Create a random owner or use the account at vm.addr(1)?
    address public SWAPPER = makeAddr("swapper");
    uint256 public constant INITIAL_DAI_SUPPLY = 1000 ether;

    function setUp() public {
        swapStablesContract = new SwapStables();
        dai = new ERC20Mock("DAI", "DAI", vm.addr(1), INITIAL_DAI_SUPPLY); // Change address to receive dai supply if necessary

        vm.prank(vm.addr(1));
        dai.transferInternal(vm.addr(1), SWAPPER, 100 ether);
    }

    function testSwapStableToETHBestPicksBestPath() public {
        // deploy a mock WETH as a simple address (use the ERC20Mock address as dummy WETH)
        ERC20Mock weth = new ERC20Mock("WETH", "WETH", vm.addr(1), 0);

        // deploy mock router and fund it with ETH for payouts
        MockUniswapV2Router router = new MockUniswapV2Router(address(weth));
        payable(address(router)).transfer(10 ether);

        // owner sets router
        vm.prank(swapStablesContract.owner());
        swapStablesContract.setRouter(address(router));

        // prepare two paths: pathA and pathB, both [DAI, WETH]
        address[] memory pathA = new address[](2);
        pathA[0] = address(dai);
        pathA[1] = address(weth);

        address[] memory pathB = new address[](2);
        pathB[0] = address(dai);
        pathB[1] = address(weth);

        // set path outputs: pathA -> 1 ETH, pathB -> 2 ETH (pathB is better)
        address[] memory setPathA = pathA;
        address[] memory setPathB = pathB;
        router.setPathOut(setPathA, 1 ether);
        router.setPathOut(setPathB, 2 ether);

        // fund the SWAPPER with 5 DAI already in setUp
        assertEq(ERC20Mock(dai).balanceOf(SWAPPER), 100 ether);

        // caller approve swapStablesContract to spend DAI
        vm.prank(SWAPPER);
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        // perform swap: caller (SWAPPER) approves contract to pull DAI
        address[][] memory paths = new address[][](2);
        paths[0] = pathA;
        paths[1] = pathB;

        vm.prank(SWAPPER);
        // first approve the contract to pull tokens
        ERC20Mock(dai).approveInternal(SWAPPER, address(swapStablesContract), 10 ether);

        vm.prank(SWAPPER);
        swapStablesContract.swapStableToETHBest(address(dai), 10 ether, paths, 0, block.timestamp + 1 hours);

        // Ensure the SwapStables contract no longer holds the DAI (it transferred to router via approvals/transferFrom)
        assertEq(ERC20Mock(dai).balanceOf(address(swapStablesContract)), 0);
    }

    /**
     * Things to test:
     * Can transferFrom Stables: DAI, USDC? ✅
     * to send to UniSwap
     * Reverts if no tokens sent
     * Can calculate gas required to send stables, do the swap and send the ETH back
     * Reverts if not enough gas is provided
     * Can parse address to ENS and ENS to address
     */
    function testCanReceiveStableCoins() public {
        assertEq(ERC20Mock(dai).balanceOf(SWAPPER), 100 ether);

        vm.startBroadcast(SWAPPER);
        ERC20Mock(dai).transferInternal(SWAPPER, address(swapStablesContract), 10 ether);
        vm.stopBroadcast();
        assertEq(ERC20Mock(dai).balanceOf(address(swapStablesContract)), 10 ether);
        assertEq(ERC20Mock(dai).balanceOf(SWAPPER), 90 ether);
    }
}
