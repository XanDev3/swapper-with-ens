import Image from "next/image";

interface logoProps {
  url: string;
  tokenName: string;
  tokenSymbol?: string;
}

export const TokenLogoAndSymbol = ({ url, tokenName, tokenSymbol }: logoProps) => {
  return (
    <div className="shrink-0 flex">
      <Image src={url} height={40} width={40} alt={tokenName} />
      {/* hide symbol on small/mobile (default hidden), show from `sm` and up */}
      <div className="ml-2 hidden sm:inline-flex items-center ">{tokenSymbol}</div>
    </div>
  );
};
