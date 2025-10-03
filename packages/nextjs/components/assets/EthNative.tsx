import ethereumLogo from "./images/ethereum-logo.png";
import * as chains from "viem/chains";

export interface InteractiveToken {
  name: string;
  symbol: string;
  address: string;
  chain: chains.Chain;
  color: string;
  logoUrl: string;
}

export const EthNative: InteractiveToken = {
  name: "Ethereum",
  symbol: "ETH",
  address: "NATIVE",
  chain: chains.mainnet,
  color: "#627EEA",
  logoUrl: ethereumLogo.src,
};
