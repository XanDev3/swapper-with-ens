# Integration tests (mainnet fork) — SwapStables

This document describes how to run and reason about the integration tests for `SwapStables`.

These tests exercise `SwapStables` against a mainnet fork using the real Uniswap V2 router and real token pools. They are intended to validate pricing, path selection, slippage behavior, deadlines, and large-swap effects under real-world liquidity.

---

## Prerequisites

- Foundry (`forge`) installed and configured. See https://book.getfoundry.sh/
- An RPC provider with mainnet access (Alchemy / Infura). The repo keeps the Alchemy key in `packages/foundry/.env` as `ALCHEMY_API_KEY`.
  - `packages/foundry/.env` (already present in the repo) contains:
    - `ALCHEMY_API_KEY` — your Alchemy project key
    - `ETHERSCAN_API_KEY` — optional (used for verification)
- A local terminal with environment variables set (or rely on `packages/foundry/.env` with your key populated).

Note: The repo's `packages/foundry/.env` shows placeholder values; copy/update that file with your real API key if needed.

---

## Fork URL and block pinning

You can construct a fork URL from `ALCHEMY_API_KEY` like:

```bash
export FORK_URL="https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY"
```

For determinism pin a block number with `FORK_BLOCK`. Pick a recent block where the Uniswap pools you intend to test are healthy.

Example:

```bash
export FORK_BLOCK=18000000    # choose a block appropriate for your tests
```

You should run tests by passing the fork URL and (optionally) block to the `forge test` CLI. Fork creation inside tests (with `vm.createFork`) has been removed from the shared helpers in this repo and is intentionally left to the test runner/CI for stability and to avoid OS socket path issues. Use the CLI approach below for local runs.

---

## Top-level integration test command examples

Run the entire integration test file (recommended for local runs). Provide your fork URL and an optional block number:

```bash
export FORK_URL="https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY"
export FORK_BLOCK=18000000 # optional; 0 or omitted means latest
forge test --fork-url "$FORK_URL" --fork-block-number $FORK_BLOCK -vvv test/integration/SwapStablesIntegration.t.sol
```

Run a single test (match by name):

```bash
forge test --match-test testDaiToEthViaSwapStablesSucceeds --fork-url "$FORK_URL" --fork-block-number $FORK_BLOCK -vvvv
```

Note: this repository's `ForkHelpers.sol` intentionally does not create a fork inside the test process. That keeps tests portable and avoids platform-specific fork instantiation problems. If you want to create a fork in-code, add your own helper logic or temporarily call `vm.createFork(...)` in your test's `setUp()`.

---

## Test account & impersonation strategy

- Choose a single test actor (example: `address TEST_USER = vm.addr(1234)` or `makeAddr("tester")`).
- Use `vm.prank`/`vm.startPrank` and `vm.stopPrank` to impersonate a whale for token transfers:
  - Example pattern:

```solidity
// in solidity test
vm.prank(DAI_WHALE);
IERC20(DAI).transfer(TEST_USER, amount);
vm.prank(TEST_USER);
IERC20(DAI).approve(address(swapStables), amount);
```

- Use `vm.deal(TEST_USER, amount)` to fund ETH for gas.
- Label addresses for readable traces: `vm.label(DAI_WHALE, "DAI_WHALE")`.

How to pick a whale address:
- Use Etherscan token holder page and pick a top holder (prefer a non-custodial holder or a known large wallet that will provide liquidity). Avoid using contracts with special behaviours.

---

## Snapshot / revert isolation

To keep tests isolated and deterministic, snapshot the state before each test and revert after:

```solidity
uint256 snapshotId = vm.snapshot();
// ... test actions ...
vm.revertTo(snapshotId);
```

This is useful when running many integration tests in the same fork to avoid cross-test pollution.

---

## Recommended integration tests (priority list)

Start with a small, fast subset (the CI-friendly group). Expand later if you want extended coverage.

Priority tests (implement first):

1. testDaiToEthViaSwapStablesSucceeds
   - Impersonate a DAI whale, transfer DAI to the test user, approve `SwapStables`, call `swapStableToETHBest(DAI, amount, paths, amountOutMin, deadline)` and assert the ETH balance of the caller increases and DAI balance decreases.

2. testSelectsBestPathBetweenDirectAndTwoHopFork
   - Build two live paths (e.g., `[DAI,WETH]` and `[DAI,USDC,WETH]`), call router.getAmountsOut for each path and assert the contract picks the best path (compare outputs or call a thin `estimateBestOut` wrapper if needed).

3. testSlippageProtectionRevertsOnLargeSlippageFork
   - Compute expected out via router.getAmountsOut, set `amountOutMin` greater than that, expect revert, and verify no net token transfer persists.

4. testDeadlineExpiredRevertsFork
   - Provide a past deadline; expect revert and verify no tokens taken.

Extended tests (run nightly or locally when needed): large-swap price-impact tests, decimals tests (USDC vs DAI), gas/perf profiling, and fuzz runs.

---

## Important behavioral notes & gotchas

- Transfer ordering: `SwapStables.swapStableToETHBest` currently `transferFrom`s the tokens from the caller before calling the router. On a mainnet fork this means if the router (or subsequent calls) revert, the entire transaction reverts and the tokens will not be left in `SwapStables`. However, when using custom mocks that don't revert in the same way you may see different behavior — document it when you test.
- Router funding: when testing with the real Uniswap router on a fork you DO NOT need to `vm.deal(router, ...)`. The router/pairs and WETH unwrapping handle ETH flows. Only fund routers in mock scenarios.
- Revert messages: router and pair reverts may not always surface as a single readable message — use `vm.expectRevert()` broadly or assert on common error strings where appropriate.
- Rate limits: using Alchemy/Infura may hit rate limits for heavy test suites. Keep the fast-suite small; run heavy tests locally or nightly.

---

## Suggested helper API (what the repo provides)

The repository includes `test/utils/ForkHelpers.sol` with the following helpers implemented for integration tests:

- `function impersonateAndTransfer(address token, address whale, address to, uint256 amount) internal`
- `function approveAs(address owner, address token, address spender, uint256 amount) internal`
- `function setRouter(address swapStablesAddr, address owner, address router) internal` — call this using `vm.prank(owner)` semantics already in the helper
- `function routerGetAmountsOut(address router, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory)`
- Snapshot helpers: `snapshot()` / `revertTo(uint256)` plus the `useSnapshot` modifier

If you prefer to create/select forks inside tests, add a `createAndSelectFork` helper in your local copy and call `vm.createFork(...)` / `vm.selectFork(...)` in `setUp()`; the shared helpers avoid this for portability.

---

## Debugging tips

- If a test unexpectedly fails, label important addresses (`vm.label`) and print balances with `console.log` (from `forge-std/Test.sol`) to inspect state.
- Use snapshots to rerun specific parts of a failing test quickly.
- For flaky tests, pin an alternate block or use a different whale (liquidity may shift between blocks).

---

If you want, I can now scaffold the `test/integration/SwapStablesIntegration.t.sol` file and a `test/utils/ForkHelpers.sol` helper with the helpers above and the four priority tests. Tell me which fork block you'd like to pin (or I can pick a reasonable recent block) and whether to use the CLI `--fork-url` or `vm.createFork` inside tests.
