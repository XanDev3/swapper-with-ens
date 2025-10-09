import { useRef } from "react";
import { TokenLogoAndSymbol } from "../../assets/TokenLogoAndSymbol";
import { InteractiveToken } from "../../assets/approvedTokens";
import { TokenCarousel } from "./TokenCarousel";
import { ChevronDownIcon } from "@heroicons/react/24/outline";
import { useOutsideClick } from "~~/hooks/scaffold-eth";

interface TokenSelectDropdownProps {
  stableToken: InteractiveToken;
  setStableToken: (token: InteractiveToken) => void;
}

export const TokenSelectDropdown = ({ stableToken, setStableToken }: TokenSelectDropdownProps) => {
  const dropdownRef = useRef<HTMLDetailsElement>(null);

  const closeDropdown = () => {
    dropdownRef.current?.removeAttribute("open");
  };

  const selectToken = (token: InteractiveToken) => {
    setStableToken(token);
    closeDropdown();
  };

  useOutsideClick(dropdownRef, closeDropdown);
  return (
    <>
      <details ref={dropdownRef} className="dropdown dropdown-end leading-3 relative inline-block ">
        <summary
          className="btn btn-secondary btn-xs sm:btn-sm  pl-0 pr-2 shadow-md dropdown-toggle gap-0 sm:gap-1/2 h-auto w-auto flex items-center  not-sm:bg-transparent not-sm:border-none not-sm:shadow-none"
          aria-haspopup="menu"
          role="button"
        >
          <TokenLogoAndSymbol url={stableToken.logoUrl} tokenName={stableToken.name} tokenSymbol={stableToken.symbol} />
          <ChevronDownIcon className="h-6 w-4 ml-0 md:ml-1 shrink-0" />
        </summary>
        <ul className="dropdown-content menu bg-[#323f61] absolute left-3/8 mt-2 pr-2 rounded-lg shadow-lg min-w-[280px] max-w-md z-50">
          <TokenCarousel onSelectToken={selectToken}></TokenCarousel>
        </ul>
      </details>
    </>
  );
};
