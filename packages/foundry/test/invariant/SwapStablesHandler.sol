// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SwapStables } from "../../contracts/SwapStables.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockUniswapV2Router } from "../mocks/MockUniswapV2Router.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Handler used by invariant fuzzer to exercise SwapStables safely.
contract SwapStablesHandler {
    SwapStables public swap;
    ERC20Mock public token;
    MockUniswapV2Router public router;

    constructor(SwapStables _swap, ERC20Mock _token, MockUniswapV2Router _router) {
        swap = _swap;
        token = _token;
        router = _router;
    }

    /// @notice Mint `amt` tokens to this handler, set a deterministic path output, and attempt a swap.
    /// Any revert from the swap is swallowed so the fuzzer can continue and invariants can be asserted.
    function depositAndSwap(uint256 amt) external {
        if (amt == 0) return; // harmless no-op for fuzzer

        // mint tokens to handler and approve swap contract
        token.mint(address(this), amt);
        token.approve(address(swap), amt);

        address[] memory p = new address[](2);
        p[0] = address(token);
        p[1] = router.WETH();

        address[][] memory paths = new address[][](1);
        paths[0] = p;

        // set deterministic router output so swap can succeed sometimes
        uint256 out = amt / 2;
        router.setPathOut(p, out);

        // call swap and swallow errors to avoid failing the invariant harness
        try swap.swapStableToETHBest(address(token), amt, paths, 0, block.timestamp + 1 hours) {
            // success - nothing to do
        } catch {
            // ignore revert - this lets us assert invariants afterwards
        }
    }

    /// @notice Helper: return token balance of this handler
    function myTokenBalance() external view returns (uint256) {
        return IERC20(address(token)).balanceOf(address(this));
    }

    /// @notice Helper: request router to set a path output (exposed for fuzzer control)
    function setRouterOut(address[] calldata path, uint256 out) external {
        router.setPathOut(path, out);
    }
}
