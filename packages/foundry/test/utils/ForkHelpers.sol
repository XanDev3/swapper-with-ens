// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/SwapStables.sol";

/// @notice Minimal Uniswap V2 router interface used by tests (renamed to avoid collisions)
interface IUniswapV2Router02Minimal {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

/// @title ForkHelpers
/// @notice Utilities for integration tests (impersonation, helper calls). Fork creation is intentionally
/// left to the test runner (CLI) as requested by the repository maintainer.
abstract contract ForkHelpers is Test {
    /// Impersonate `whale` and transfer `amount` of `token` to `to`
    function impersonateAndTransfer(address token, address whale, address to, uint256 amount) internal {
        vm.prank(whale);
        IERC20(token).transfer(to, amount);
    }

    /// Approve `spender` on behalf of `owner` for `amount` of `token`
    function approveAs(address owner, address token, address spender, uint256 amount) internal {
        vm.prank(owner);
        IERC20(token).approve(spender, amount);
    }

    /// Label an address for easier debugging in traces
    function label(address addr, string memory name) internal {
        vm.label(addr, name);
    }

    /// Fund an address with ETH for gas
    function fund(address who, uint256 amount) internal {
        vm.deal(who, amount);
    }

    /// Set SwapStables router to `router` using owner's authority
    /// Set SwapStables router to `router` using owner's authority
    /// NOTE: SwapStables now requires the router in its constructor and has no setter. For forked
    /// deployments where the SwapStables instance is already deployed, this helper will attempt a
    /// low-level call to setRouter (for backwards compatibility). If that fails, tests should redeploy
    /// a new SwapStables instance with the desired router.
    function setRouter(address swapStablesAddr, address owner, address router) internal {
        // attempt to call setRouter via low-level call (will revert if function doesn't exist)
        vm.prank(owner);
        (bool ok,) = swapStablesAddr.call(abi.encodeWithSignature("setRouter(address)", router));
        if (!ok) {
            // cannot set router on existing contract; test should redeploy instead. Emit label for clarity.
            vm.label(swapStablesAddr, "SwapStables_no_setter");
        }
    }

    /// Get router amounts out for a path (calls the real UniswapV2 router on whichever fork is selected by the runner)
    function routerGetAmountsOut(address router, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory)
    {
        return IUniswapV2Router02Minimal(router).getAmountsOut(amountIn, path);
    }

    /// Snapshot and revert helpers
    function snapshot() internal returns (uint256) {
        return vm.snapshot();
    }

    function revertTo(uint256 id) internal {
        vm.revertTo(id);
    }

    /// Modifier to snapshot state before a test and revert after, keeping fork isolated
    modifier useSnapshot() {
        uint256 id = vm.snapshot();
        _;
        vm.revertTo(id);
    }
}
