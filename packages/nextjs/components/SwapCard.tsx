"use client";

import React, { useEffect, useState } from "react";
import { TokenSelectDropdown } from "./NavBar/Modal/TokenSelectDropdown";
import { EthNative } from "./assets/EthNative";
import { TokenLogoAndSymbol } from "./assets/TokenLogoAndSymbol";
import { InteractiveToken, approvedERC20 } from "./assets/approvedTokens";
import { chainsToContracts, erc20Abi } from "./assets/constants";
import { formatUnits, getContract, parseUnits } from "viem";
import { useAccount, usePublicClient, useWalletClient } from "wagmi";
import { Bars3Icon } from "@heroicons/react/24/outline";
import {
  useDeployedContractInfo,
  useScaffoldContract,
  useScaffoldWriteContract,
  useTransactor,
} from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { useWatchBalance } from "~~/hooks/scaffold-eth/useWatchBalance";
import useUniswapPrice from "~~/hooks/useUniswapPrice";
import { AllowedChainIds } from "~~/utils/scaffold-eth";
import { notification } from "~~/utils/scaffold-eth/notification";

export default function SwapCard() {
  /* States */
  const [amount, setAmount] = useState("0");
  const [stableToken, setStableToken] = useState<InteractiveToken>(approvedERC20[1]); // lifted state
  const [ethPrice, setEthPrice] = useState(0.0);
  const [ethPerStablePrice, setEthPerStablePrice] = useState(0);
  const [isPriceLoading, setIsPriceLoading] = useState(false);
  const [isOpenSettings, setOpenSettings] = useState(false);
  // flash flag for small UI color animation when price updates
  const [priceUpdated, setPriceUpdated] = useState(false);
  // UI states for on-chain operations
  const [isApproving, setIsApproving] = useState(false);
  const [isSwapping, setIsSwapping] = useState(false);

  const { address, chain } = useAccount();
  const { data: walletClient } = useWalletClient();
  const writeTx = useTransactor();

  // contract hooks
  const { targetNetwork } = useTargetNetwork();
  const publicClient = usePublicClient({ chainId: targetNetwork?.id });
  const { data: deployedSwap } = useDeployedContractInfo({
    contractName: "SwapStables",
    chainId: targetNetwork?.id as AllowedChainIds,
  });
  const { data: swapContract } = useScaffoldContract({
    contractName: "SwapStables",
    walletClient: walletClient ?? undefined,
  });
  // Use scaffold write helper which wraps simulation & transactor
  const { writeContractAsync: writeSwapAsync } = useScaffoldWriteContract({
    contractName: "SwapStables",
    chainId: targetNetwork?.id as any,
  });

  // Fetch balance for selected token
  const { data: balanceData } = useWatchBalance({
    address: address,
    token: stableToken.address as `0x${string}`,
  });

  /* Balance formatting */
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

  /* useEffects  */
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

  const onSwapClick = async () => {
    // basic validation
    if (!address) return notification.error("Connect wallet to swap");
    if (!amount || Number(amount) <= 0) return notification.error("Enter an amount > 0");
    if (!swapContract) return notification.error("Swap contract not loaded");
    const chainId = targetNetwork?.id ?? 31337;

    // ensure wallet is connected to the same network as the targetNetwork for writes
    if (chain?.id && targetNetwork?.id && chain.id !== targetNetwork.id) {
      notification.error(`Please switch your wallet network to ${targetNetwork.name} before attempting the swap`);
      return;
    }

    // compute swap address (prefer deployed metadata, fall back to constants)
    const swapAddressFromDeployed = deployedSwap?.address as `0x${string}` | undefined;
    const swapAddressFromConstants = chainsToContracts[chainId]?.SwapStables as `0x${string}` | undefined;
    const swapAddress = swapAddressFromDeployed ?? swapAddressFromConstants;
    const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" as `0x${string}`;

    try {
      const stableAmount = parseUnits(amount, balanceData?.decimals ?? 18);

      // 1) approve if needed
      setIsApproving(true);
      notification.info(`Checking allowance for ${stableToken.symbol}...`);

      if (!walletClient || !publicClient) {
        notification.error("Wallet client or public client not available");
        setIsApproving(false);
        return;
      }

      if (!swapAddress) {
        notification.error("Swap contract not deployed on selected network");
        setIsApproving(false);
        return;
      }

      const tokenContract = getContract({
        address: stableToken.address as `0x${string}`,
        abi: erc20Abi as any,
        client: {
          public: publicClient,
          wallet: walletClient,
        },
      });

      const allowance = (await tokenContract.read.allowance([address as `0x${string}`, swapAddress])) as bigint;
      if (allowance < stableAmount) {
        notification.info(`Requesting approval for ${stableToken.symbol}...`);
        // viem's contract.write functions expect an array of args as the first parameter
        const makeApprove = () => tokenContract.write.approve([swapAddress, stableAmount] as any);
        await writeTx(makeApprove);

        // re-check allowance to ensure approval went through before proceeding
        const newAllowance = (await tokenContract.read.allowance([address as `0x${string}`, swapAddress])) as bigint;
        if (newAllowance < stableAmount) {
          notification.error("Approval did not complete. Please try again.");
          setIsApproving(false);
          return;
        }

        notification.success("Approval submitted");
      } else {
        notification.info("Sufficient allowance, skipping approval");
      }
    } catch (e: any) {
      console.error(e);
      notification.error("Approval failed: " + (e?.message ?? ""));
    } finally {
      setIsApproving(false);
    }

    // 2) perform swap
    try {
      setIsSwapping(true);
      notification.info("Preparing swap transaction...");

      if (!walletClient || !publicClient) {
        notification.error("Wallet client or public client not available");
        setIsApproving(false);
        return;
      }

      // build simple args: tokenIn, amountIn, paths, amountOutMin, deadline
      const tokenIn = stableToken.address as `0x${string}`;
      const amountIn = parseUnits(amount, balanceData?.decimals ?? 18);
      const DEFAULT_SLIPPAGE = 0.01; // 1%

      // Note: SwapStables expects address[][] calldata paths. For now we pass a single direct path [tokenIn, WETH]
      const wethAddress = chainsToContracts[chainId]?.weth as `0x${string}`;
      const paths = [[tokenIn, wethAddress]];
      let amountOutMin;

      // getAmountsOut on router in order to calculate slippage and set amountOutMin
      const routerAbi = [
        {
          type: "function",
          name: "getAmountsOut",
          inputs: [
            { name: "amountIn", type: "uint256" },
            { name: "path", type: "address[]" },
          ],
          outputs: [{ name: "amounts", type: "uint256[]" }],
          stateMutability: "view",
        },
      ];

      const path = paths[0];
      const estimatedAmountsOut = await publicClient.readContract({
        address: routerAddress,
        abi: routerAbi as any,
        functionName: "getAmountsOut",
        args: [amountIn, path],
      });

      if (estimatedAmountsOut && Array.isArray(estimatedAmountsOut) && estimatedAmountsOut.length > 0) {
        const out = BigInt(estimatedAmountsOut[estimatedAmountsOut.length - 1]);
        // integer math: amountOutMin = out - floor(out * 0.01) converted to BigInt
        amountOutMin = out - (out * BigInt(1)) / BigInt(100);
      } else {
        // Could not get quote from router so use local ethPerStablePrice
        const decimals = balanceData?.decimals ?? 18;
        const amountFloat = Number(formatUnits(amountIn, decimals));
        const estimatedOut = amountFloat * ethPerStablePrice;
        if (!estimatedOut || !isFinite(estimatedOut) || estimatedOut <= 0) amountOutMin = 0;
        const adjustedOutStr = (estimatedOut * (1 - DEFAULT_SLIPPAGE)).toFixed(18);
        amountOutMin = parseUnits(adjustedOutStr, 18) as bigint;
      }

      const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from now

      // sanity check: ensure contract code exists at the swap address on the configured RPC
      const code = await publicClient?.getCode({ address: swapAddress as `0x${string}` });
      if (!code || code === "0x" || code === "0x0") {
        notification.error(
          `No contract code found at ${swapAddress} on the selected RPC. Did you deploy the contract to this network?`,
        );
        setIsSwapping(false);
        return;
      }

      const tx = await writeSwapAsync({
        functionName: "swapStableToETHBest",
        args: [tokenIn, amountIn, paths, BigInt(amountOutMin), BigInt(deadline)],
      });
      if (tx) {
        notification.success("Swap submitted, awaiting confirmation...");
      }
    } catch (e: any) {
      console.error(e);
      notification.error("Swap failed: " + (e?.message ?? ""));
    } finally {
      setIsSwapping(false);
    }
  };

  return (
    <div className="mx-auto w-full max-w-lg px-4">
      <div className="rounded-3xl bg-white/6 backdrop-blur-lg border border-white/10 p-6 shadow-2xl">
        <div className="flex items-start justify-between">
          <div>
            <h2 className="text-2xl font-semibold text-white">Swap Stable → ETH</h2>
            <p className="text-sm text-gray-300 mt-1">Swap DAI/USDC on Uniswap v2</p>
          </div>
          <Bars3Icon onClick={() => setOpenSettings(!isOpenSettings)} className="h-5 w-5" />
        </div>

        <div className="mt-6 space-y-4">
          {/* From row */}
          <div className="flex items-center justify-between bg-white/4 rounded-xl p-3">
            <div className="flex items-center gap-2">
              <button className="btn-sm">
                <TokenSelectDropdown stableToken={stableToken} setStableToken={setStableToken}></TokenSelectDropdown>
              </button>

              <div>
                <div className="text-sm text-gray-200">From</div>
                <div className="text-xs text-gray-400 md:text-nowrap ">
                  Balance: {formattedBalance} {stableToken.symbol}
                </div>
              </div>
            </div>
            <input
              type="text"
              className="bg-transparent text-right text-2xl font-medium md:max-w-40 max-w-[30%] shrink-1 outline-none wrap-normal"
              value={amount}
              onChange={e => setAmount(e.target.value)}
            />
          </div>

          {/* To row */}
          <div className="flex items-center justify-between bg-white/3 rounded-xl p-3">
            <div className="flex items-center gap-2">
              <TokenLogoAndSymbol url={EthNative.logoUrl} tokenName={EthNative.name} />
              <div>
                <div className="text-sm text-gray-200">To</div>
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
                ≈ {(Number(amount) * ethPerStablePrice).toFixed(8)} ETH
              </div>
              <div
                className={`text-xs transition-colors duration-300 ${priceUpdated ? "text-gray-400/75" : "text-gray-400"}`}
              >
                ETH Price: {ethPrice.toFixed(2)} ETH/{stableToken.symbol}
              </div>
            </div>
          </div>

          {/* NEEDS SWAP FUNCTIONALITY */}
          {/* CTA */}
          <div className="mt-4">
            <button
              onClick={onSwapClick}
              disabled={isApproving || isSwapping}
              className={`w-full py-4 rounded-xl text-white font-semibold shadow-lg hover:scale-[1.02] transition-transform ${
                isApproving || isSwapping
                  ? "opacity-60 cursor-not-allowed bg-gray-500"
                  : "bg-gradient-to-r from-indigo-500 to-purple-500"
              }`}
            >
              {isApproving ? "Approving..." : isSwapping ? "Swapping..." : "Swap Now"}
            </button>
          </div>

          {/* NEEDS UPDATING */}
          {/* collapsible settings */}
          {isOpenSettings && (
            <div className="mt-4 p-3 rounded-lg bg-white/3 text-sm text-gray-300">
              <div className="flex items-center justify-between">
                <div>Slippage tolerance</div>
                <div>1%</div>
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
