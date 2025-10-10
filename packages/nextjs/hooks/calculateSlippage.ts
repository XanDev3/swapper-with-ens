/* import { useAccount, usePublicClient, useWalletClient } from "wagmi";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";


const copilotPromt = `I would like to set a reasonable slippage tolerance as a default value. In the UI we display "0.5%" as the tolerance. 
1. Is that a fair value for the USDC/WETH and DAI/WETH pools in uniswapV2?
2. If that is a fair and potentially loss-minimizing-value can we make sure we are using that percentage to calculate max slippage from the amount of wETH we show in the UI and provide that slippage as the amountOutMin?
3. It seems to me that by setting the amountOutMin = 0 that we are allowing users to not receive any wEth back from the swap. Please correct me if I am wrong and suggest edits for 2. if that is the case.`
async function calculateSlippage(
      tokenIn: `0x${string}`,
      wethAddress: `0x${string}`,
      amountIn: bigint,
      chainId: number,
      swapAddr?: `0x${string}` | undefined,
    ): Promise<bigint | null> {
      const { targetNetwork } = useTargetNetwork();    
      const publicClient = usePublicClient({ chainId: targetNetwork?.id });
      const DEFAULT_SLIPPAGE = 0.005; // 1%

      // 1) On-chain quoting via router.getAmountsOut
      try {
        if (!publicClient) throw new Error("publicClient not available");

        // read uniV2() from SwapStables if available
        let routerAddress: `0x${string}` | undefined;
        if (swapAddr) {
          try {
            const swapAbi = [
              {
                type: "function",
                name: "uniV2",
                inputs: [],
                outputs: [{ name: "", type: "address", internalType: "contract IUniswapV2Router02" }],
                stateMutability: "view",
              },
            ];
            const uni = await publicClient.readContract({
              address: swapAddr as `0x${string}`,
              abi: swapAbi as any,
              functionName: "uniV2",
              args: [],
            });
            if (uni) routerAddress = uni as `0x${string}`;
          } catch (e) {
            // ignore and fallback
          }
        }

        // fallback to canonical UniswapV2 router only on mainnet
        if (!routerAddress && chainId === 1) {
          routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" as `0x${string}`;
        }

        if (routerAddress) {
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

          const path = [tokenIn, wethAddress];
          const amountsOut = await publicClient.readContract({
            address: routerAddress,
            abi: routerAbi as any,
            functionName: "getAmountsOut",
            args: [amountIn, path],
          });

          if (amountsOut && Array.isArray(amountsOut) && amountsOut.length > 0) {
            const out = BigInt(amountsOut[amountsOut.length - 1]);
            // integer math: amountOutMin = out - floor(out * 0.005)
            return out - (out * BigInt(5)) / BigInt(1000);
          }
        }
      } catch (err) {
        console.error("On-chain quote failed", err);
      }

      // 2) Fallback to UI price (ethPerStablePrice)
      try {
        const decimals = balanceData?.decimals ?? 18;
        const amountFloat = Number(formatUnits(amountIn, decimals));
        if (!amountFloat || !isFinite(amountFloat) || amountFloat <= 0) return null;
        const estimatedOut = amountFloat * ethPerStablePrice;
        if (!estimatedOut || !isFinite(estimatedOut) || estimatedOut <= 0) return null;
        const adjustedOutStr = (estimatedOut * (1 - DEFAULT_SLIPPAGE)).toFixed(18);
        return parseUnits(adjustedOutStr, 18) as bigint;
      } catch (err) {
        console.error("Fallback estimate failed", err);
        return null;
      }
    } */
