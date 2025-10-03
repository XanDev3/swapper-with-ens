import { ChainWithAttributes, getAlchemyHttpUrl } from "./networks";
import { CurrencyAmount, Token } from "@uniswap/sdk-core";
import { Pair, Route } from "@uniswap/v2-sdk";
import { Address, createPublicClient, fallback, http, parseAbi } from "viem";
import { mainnet } from "viem/chains";

const alchemyHttpUrl = getAlchemyHttpUrl(mainnet.id);
const rpcFallbacks = alchemyHttpUrl ? [http(alchemyHttpUrl), http()] : [http()];
const publicClient = createPublicClient({
  chain: mainnet,
  transport: fallback(rpcFallbacks),
});

const ABI = parseAbi([
  "function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function token0() external view returns (address)",
  "function token1() external view returns (address)",
]);

/* Made changes from default util provided by scaffold-eth */
export const fetchPriceFromUniswap = async (
  targetNetwork: ChainWithAttributes,
  tokenAddr: string /* added to work with USDC as well as DAI */,
): Promise<number> => {
  if (
    targetNetwork.nativeCurrency.symbol !== "ETH" &&
    targetNetwork.nativeCurrency.symbol !== "SEP" &&
    !targetNetwork.nativeCurrencyTokenAddress
  ) {
    return 0;
  }
  if (typeof tokenAddr !== "string") {
    return 0;
  }
  try {
    /* const DAI = new Token(1, "0x6B175474E89094C44Da98b954EedeAC495271d0F", 18);
    const USDC = new Token(1,"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 6); */
    const STABLETOKEN =
      tokenAddr === "0x6B175474E89094C44Da98b954EedeAC495271d0F"
        ? new Token(1, tokenAddr, 18)
        : new Token(1, tokenAddr, 6);
    const TOKEN = new Token(
      1,
      targetNetwork.nativeCurrencyTokenAddress || "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      18,
    );

    const pairAddress = Pair.getAddress(TOKEN, STABLETOKEN) as Address;

    const wagmiConfig = {
      address: pairAddress,
      abi: ABI,
    };

    const reserves = await publicClient.readContract({
      ...wagmiConfig,
      functionName: "getReserves",
    });

    const token0Address = await publicClient.readContract({
      ...wagmiConfig,
      functionName: "token0",
    });

    const token1Address = await publicClient.readContract({
      ...wagmiConfig,
      functionName: "token1",
    });
    const token0 = [TOKEN, STABLETOKEN].find(token => token.address === token0Address) as Token;
    const token1 = [TOKEN, STABLETOKEN].find(token => token.address === token1Address) as Token;
    const pair = new Pair(
      CurrencyAmount.fromRawAmount(token0, reserves[0].toString()),
      CurrencyAmount.fromRawAmount(token1, reserves[1].toString()),
    );
    const route = new Route([pair], TOKEN, STABLETOKEN);
    const price = parseFloat(route.midPrice.toSignificant(18));
    return price;
  } catch (error) {
    console.error(
      `useNativeCurrencyPrice - Error fetching ${targetNetwork.nativeCurrency.symbol} price from Uniswap: `,
      error,
    );
    return 0;
  }
};
