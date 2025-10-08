// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { SwapStables } from "../../contracts/SwapStables.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockUniswapV2Router } from "../mocks/MockUniswapV2Router.sol";
import { SwapStablesHandler } from "./SwapStablesHandler.sol";

contract SwapStablesInvariant is Test {
    SwapStables public swap;
    ERC20Mock public token;
    MockUniswapV2Router public router;
    SwapStablesHandler public handler;

    function setUp() public {
        swap = new SwapStables();
        token = new ERC20Mock("MOCK", "MOCK", vm.addr(1), 0);
        router = new MockUniswapV2Router(vm.addr(2));
        vm.deal(address(router), 100 ether);
        vm.prank(swap.owner());
        swap.setRouter(address(router));

        handler = new SwapStablesHandler(swap, token, router);

        // register handler as a target contract for invariants
        targetContract(address(handler));
    }

    // invariant: SwapStables contract should never retain non-zero token balances for tokens it swaps
    function invariant_swapContractDoesntHoldToken() public view {
        uint256 bal = token.balanceOf(address(swap));
        assertEq(bal, 0);
    }
}
