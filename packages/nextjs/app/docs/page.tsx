"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";

const DocsPage = () => {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const outerClassName =
    mounted && resolvedTheme === "light"
      ? "min-h-screen bg-gradient-to-b from-pink-700 via-purple-800 to-indigo-900 text-white"
      : "min-h-screen bg-gradient-to-b from-indigo-900 via-purple-800 to-pink-700 text-white";

  return (
    <div className={outerClassName}>
      <main className="py-12 px-4 sm:px-8 max-w-4xl mx-auto">
        <header className="mb-8">
          <h1 className="text-4xl lg:text-5xl font-extrabold leading-tight text-white">SwapStables — Overview</h1>
          <p className="mt-3 text-lg text-gray-200/90 max-w-3xl">
            A minimal demo dApp that swaps supported stable ERC‑20 tokens (DAI, USDC) into native ETH via Uniswap V2 and
            forwards the ETH back to the caller. The project pairs a small contract surface with a compact Scaffold‑ETH
            frontend.
          </p>
        </header>

        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-white">What the contract does</h2>
          <p className="mt-2 text-base text-gray-200/90 leading-relaxed">
            The core contract, <code className="bg-white/20 px-1 py-0.5 rounded">SwapStables.sol</code>, accepts an
            input stable token, evaluates candidate Uniswap V2 paths using{" "}
            <code className="bg-white/20 px-1 py-0.5 rounded">getAmountsOut</code>, executes the best{" "}
            <code className="bg-white/20 px-1 py-0.5 rounded">swapExactTokensForETH</code>, and then forwards the
            received ETH to the caller.
          </p>

          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <div className="bg-white/5 p-4 rounded-lg">
              <h3 className="text-sm font-semibold text-gray-100">Key checks</h3>
              <ul className="mt-2 text-sm text-gray-200/80 list-disc list-inside space-y-1">
                <li>Non-zero input amount and non-empty path list.</li>
                <li>Local deadline enforcement (30 minutes).</li>
                <li>
                  Checks return values from <code className="bg-white/20 px-1 py-0.5 rounded">transferFrom</code> and{" "}
                  <code className="bg-white/20 px-1 py-0.5 rounded">approve</code>.
                </li>
                <li>Uses custom errors to reduce gas and clarify failure modes.</li>
              </ul>
            </div>

            <div className="bg-white/5 p-4 rounded-lg">
              <h3 className="text-sm font-semibold text-gray-100">Behaviour</h3>
              <p className="mt-2 text-sm text-gray-200/80 leading-relaxed">
                The contract approves the router (resets to zero in case of partial allowance then sets to desired
                amount), performs the swap, and then attempts to forward ETH to the original caller using a safe{" "}
                <code className="bg-white/20 px-1 py-0.5 rounded">call</code>.
              </p>
            </div>
          </div>
        </section>

        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-white">Swap flow (high-level)</h2>
          <ol className="mt-3 list-decimal list-inside space-y-2 text-gray-200/90">
            <li>User approves the contract to spend the stable token for a given amount.</li>
            <li>
              Frontend constructs candidate paths (e.g.{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">DAI → WETH</code>,{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">DAI → USDC → WETH</code>).
            </li>
            <li>
              Contract pulls tokens, selects the best path via{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">getAmountsOut</code>, executes the swap, and receives
              ETH.
            </li>
            <li>
              Contract forwards ETH to the caller and emits{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">SwapExecuted</code>.
            </li>
          </ol>
        </section>

        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-white">Addresses & tokens</h2>
          <p className="mt-2 text-gray-200/90">For the demo and UI we focus on two canonical, highly-liquid stables:</p>

          <ul className="mt-4 space-y-2 text-gray-200/90">
            <li>
              DAI (mainnet):{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">0x6B175474E89094C44Da98b954EedeAC495271d0F</code>
            </li>
            <li>
              USDC (mainnet):{" "}
              <code className="bg-white/20 px-1 py-0.5 rounded">0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48</code>
            </li>
          </ul>

          <p className="mt-4 text-gray-200/80 text-sm">
            Why only DAI and USDC? These tokens are chosen to keep the demo focused and reliable: high liquidity, varied
            decimals, and a simple UI surface to exercise token handling in tests.
          </p>
        </section>

        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-white">Developer notes</h2>
          <p className="mt-2 text-gray-200/90 leading-relaxed">
            Run Foundry/Forge unit and integration tests under{" "}
            <code className="bg-white/20 px-1 py-0.5 rounded">packages/foundry/test</code>, and use an Anvil mainnet
            fork for integration. Ensure <code className="bg-white/20 px-1 py-0.5 rounded">RPC_URL</code> is configured
            for forks.
          </p>

          <div className="mt-4">
            <pre className="bg-gray-900/50 rounded p-3 text-sm overflow-auto">
              <code>
                # run unit tests (foundry)
                {"\n"}cd packages/foundry
                {"\n"}forge test
              </code>
            </pre>
          </div>
        </section>

        <section className="mb-12">
          <h2 className="text-2xl font-semibold text-white">Security & limitations</h2>
          <ul className="mt-3 text-gray-200/90 list-disc list-inside space-y-1 text-sm">
            <li>Demo-only — do not deploy large funds on mainnet without review/audit.</li>
            <li>Router and paths are trusted; ensure supplied paths end in WETH.</li>
            <li>
              Slippage protection relies on <code className="bg-white/7 px-1 rounded">amountOutMin</code> passed by
              caller.
            </li>
          </ul>
        </section>

        <footer className="pb-12 text-sm text-gray-300/80">
          <p>
            Want enhancements? Add a token whitelist, UI token selector, or monitoring/alerts for production readiness.
          </p>
        </footer>
      </main>
    </div>
  );
};

export default DocsPage;
