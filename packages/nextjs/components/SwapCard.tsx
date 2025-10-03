"use client";

import React, { useEffect, useState } from "react";
import { TokenSelectDropdown } from "./NavBar/Modal/TokenSelectDropdown";
import { EthNative } from "./assets/EthNative";
import { TokenLogoAndSymbol } from "./assets/TokenLogoAndSymbol";
import { InteractiveToken, approvedERC20 } from "./assets/approvedTokens";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";
import { Bars3Icon } from "@heroicons/react/24/outline";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { useWatchBalance } from "~~/hooks/scaffold-eth/useWatchBalance";
import useUniswapPrice from "~~/hooks/useUniswapPrice";
import { notification } from "~~/utils/scaffold-eth/notification";

export default function SwapCard() {
  const [amount, setAmount] = useState(0);
  const [stableToken, setStableToken] = useState<InteractiveToken>(approvedERC20[1]); // lifted state
  const [ethPrice, setEthPrice] = useState(0.0);
  const [ethPerStablePrice, setEthPerStablePrice] = useState(0);
  const [isPriceLoading, setIsPriceLoading] = useState(false);
  const [isOpenSettings, setOpenSettings] = useState(false);
  // flash flag for small UI color animation when price updates
  const [priceUpdated, setPriceUpdated] = useState(false);

  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();

  // Fetch balance for selected token
  const { data: balanceData } = useWatchBalance({
    address: address,
    token: stableToken.address as `0x${string}`,
  });

  const formattedBalance = balanceData
    ? parseFloat(formatUnits(balanceData.value, balanceData.decimals)).toFixed(2)
    : "0";

  // Use the shared hook for polling + caching
  const {
    price: rawPrice,
    isLoading: hookLoading,
    error: hookError,
  } = useUniswapPrice({
    targetNetwork,
    stableAddress: stableToken.address,
    intervalMs: 15000,
    ttlMs: 14000,
  });

  // keep local states in sync with hook
  useEffect(() => {
    if (hookError) {
      try {
        notification.error(`Could not fetch price: ${hookError.message}`);
      } catch {}
    }
  }, [hookError]);

  useEffect(() => {
    setIsPriceLoading(hookLoading);
  }, [hookLoading]);

  // rawPrice is stable-per-ETH (e.g. DAI per ETH). compute ETH per stable for display
  useEffect(() => {
    if (rawPrice && rawPrice > 0) {
      setEthPrice(Number(rawPrice));
      setEthPerStablePrice(1 / rawPrice);
      // flash UI to indicate a price update
      setPriceUpdated(true);
      const t = setTimeout(() => setPriceUpdated(false), 1000);
      return () => clearTimeout(t);
    }
  }, [rawPrice]);

  return (
    <div className="mx-auto w-full max-w-lg px-4">
      <div className="rounded-3xl bg-white/6 backdrop-blur-lg border border-white/10 p-6 shadow-2xl">
        <div className="flex items-start justify-between">
          <div>
            <h2 className="text-2xl font-semibold text-white">Swap Stable → wETH</h2>
            <p className="text-sm text-gray-300 mt-1">Auto-selects most profitable path on Uniswap v2</p>
          </div>
          <Bars3Icon onClick={() => setOpenSettings(!isOpenSettings)} className="h-5 w-5" />
        </div>

        <div className="mt-6 space-y-4">
          {/* From row */}
          <div className="flex items-center justify-between bg-white/4 rounded-xl p-3">
            <div className="flex items-center gap-3">
              <button>
                <TokenSelectDropdown stableToken={stableToken} setStableToken={setStableToken}></TokenSelectDropdown>
              </button>

              <div>
                <div className="text-sm text-gray-200">From</div>
                <div className="text-xs text-gray-400 text-nowrap">
                  Balance: {formattedBalance} {stableToken.symbol}
                </div>
              </div>
            </div>
            <input
              className="bg-transparent text-right text-2xl font-medium max-w-40 outline-none wrap-normal"
              value={amount}
              onChange={e => setAmount(Number(e.target.value) || 0)}
            />
          </div>

          {/* To row */}
          <div className="flex items-center justify-between bg-white/3 rounded-xl p-3">
            <div className="flex items-center gap-3">
              <TokenLogoAndSymbol url={EthNative.logoUrl} tokenName={EthNative.name} />
              <div>
                <div className="text-sm text-gray-200">To</div>
                {/* <div className="text-xs text-gray-400 w-1/5">
                                    WETH 
                                    ➜ 
                                    unwrap to ETH
                                </div> */}
              </div>
            </div>
            <div className="text-right">
              <div
                className={`text-2xl font-semibold flex items-center justify-end gap-2 transition-colors duration-300 ${priceUpdated ? "text-white/75" : "text-white"}`}
              >
                {isPriceLoading ? (
                  <svg className="animate-spin h-5 w-5 text-gray-300" viewBox="0 0 24 24">
                    <circle
                      className="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      strokeWidth="4"
                      fill="none"
                    ></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path>
                  </svg>
                ) : null}
                ≈ {(amount * ethPerStablePrice).toFixed(8)} wETH
              </div>
              <div
                className={`text-xs transition-colors duration-300 ${priceUpdated ? "text-gray-400/75" : "text-gray-400"}`}
              >
                wETH Price: {ethPrice.toFixed(2)} wETH/{stableToken.symbol}
              </div>
            </div>
          </div>

          {/* NEEDS SWAP FUNCTIONALITY */}
          {/* CTA */}
          <div className="mt-4">
            <button className="w-full py-4 rounded-xl bg-gradient-to-r from-indigo-500 to-purple-500 text-white font-semibold shadow-lg hover:scale-[1.02] transition-transform">
              Swap Now
            </button>
          </div>

          {/* NEEDS UPDATING */}
          {/* gas and estimate row */}
          <div className="mt-3 flex items-center justify-between text-xs text-gray-400">
            <div>Estimated gas: 0.002 ETH</div>
          </div>

          {/* NEEDS UPDATING */}
          {/* collapsible settings */}
          {isOpenSettings && (
            <div className="mt-4 p-3 rounded-lg bg-white/3 text-sm text-gray-300">
              <div className="flex items-center justify-between">
                <div>Slippage tolerance</div>
                <div>0.5%</div>
              </div>
              <div className="mt-2 flex items-center justify-between">
                <div>Deadline</div>
                <div>20 min</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
