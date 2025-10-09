import Image from "next/image";
import { InteractiveToken, approvedERC20 } from "../../assets/approvedTokens";

const shortAddress = (addr: string) => addr.slice(0, 6) + "..." + addr.slice(-4);

const scrollKeyframes = `
  @keyframes scroll {
    0% {
      transform: translateX(0);
    }
    100% {
      transform: translateX(calc(-50%));
    }
  }
`;
function Tokens({ onSelectToken }: { onSelectToken: (token: InteractiveToken) => void }) {
  return approvedERC20.map(token => (
    <div
      className="flex items-center gap-3 pl-1 pr-4 py-1 m-2 bg-[#323f61] hover:bg-gray-400 rounded-md cursor-pointer"
      key={token.address}
      onClick={() => onSelectToken(token)}
    >
      <div className="relative w-10 h-10 flex-shrink-0 rounded-full overflow-hidden ">
        <Image alt={`${token.symbol} logo`} className="object-cover" fill src={token.logoUrl} />
      </div>

      <div className="flex flex-col">
        <div className="text-s text-gray-300 flex items-center gap-2">
          <span className="font-semibold text-[14px]">{token.symbol}</span>
          <span className="text-[14px] text-gray-400 mx-2 ">{shortAddress(token.address)}</span>
        </div>
      </div>
    </div>
  ));
}
interface TokenCarouselProps {
  onSelectToken: (token: InteractiveToken) => void;
}

export const TokenCarousel = ({ onSelectToken }: TokenCarouselProps) => {
  return (
    <>
      <style>{scrollKeyframes}</style>
      <div className="w-full max-w-md rounded-lg overflow-auto">
        <div className=" pr-4 pl-2 pt-2 mx-2 ">
          <div className="text-sm font-semibold text-left text-gray-300">Select a token</div>
        </div>

        <div className="max-h-60 overflow-auto">
          <div className="flex flex-col w-full">
            <Tokens onSelectToken={onSelectToken} />
          </div>
        </div>
      </div>
    </>
  );
};
