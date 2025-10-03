import Image from "next/image";

interface logoProps {
  url: string;
  tokenName: string;
  tokenSymbol?: string;
}

export const TokenLogoAndSymbol = ({ url, tokenName, tokenSymbol }: logoProps) => {
  return (
    <>
      <Image src={url} height={40} width={40} alt={tokenName} />
      <div className="mx-1/2">{tokenSymbol}</div>
    </>
  );
};
