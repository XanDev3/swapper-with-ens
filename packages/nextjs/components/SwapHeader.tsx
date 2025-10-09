"use client";

import React, { useRef } from "react";
import Link from "next/link";
import { Bars3Icon } from "@heroicons/react/24/outline";
import { useOutsideClick } from "~~/hooks/scaffold-eth";

export default function SwapHeader() {
  const burgerMenuRef = useRef<HTMLDetailsElement>(null);
  useOutsideClick(burgerMenuRef, () => {
    burgerMenuRef?.current?.removeAttribute("open");
  });

  return (
    <header className="w-full flex items-center justify-between py-4 px-4 md:px-8">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-500 flex items-center justify-center shadow-md">
          <span className="text-white font-semibold">S</span>
        </div>
        <Link href="/" className="text-lg font-semibold tracking-tight">
          SwapStables
        </Link>
      </div>

      <details className="dropdown" ref={burgerMenuRef}>
        <summary className="ml-1 btn btn-ghost lg:hidden hover:bg-transparent">
          <Bars3Icon className="h-1/2" />
        </summary>
        <ul
          className="menu menu-compact dropdown-content mt-3 p-2 shadow-sm bg-base-100 rounded-box w-24 absolute -right-2"
          onClick={() => {
            burgerMenuRef?.current?.removeAttribute("open");
          }}
        >
          <li className="flex items-center gap-3">
            <nav className="hidden sm:flex sm:flex-col gap-3 text-sm text-neutral">
              <a className="hover:text-gray-200" href="#">
                Docs
              </a>
              <a className="hover:text-gray-200" href="#">
                History
              </a>
            </nav>
          </li>
        </ul>
      </details>

      {/* Display links horizontally if on large screen */}
      <nav className="hidden lg:flex gap-3 text-sm text-neutral">
        <a className="hover:text-gray-200" href="#">
          Docs
        </a>
        <a className="hover:text-gray-200" href="#">
          History
        </a>
      </nav>

      {/* Using Scaffold-eth wallet connector  */}
      {/* Placeholder for RainbowKit/Wagmi connect button - replace with your ConnectButton component */}
      {/* <div className="hidden sm:block">
                    <button className="px-4 py-2 rounded-full bg-black text-white text-sm font-medium shadow-md border border-white/5">
                        Connect Wallet
                    </button>
                </div> */}

      {/* Mobile connect icon */}
      {/* <div className="sm:hidden">
                    <button className="w-10 h-10 rounded-full bg-black/80 text-white flex items-center justify-center">
                        <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" d="M12 11c2.21 0 4-1.79 4-4S14.21 3 12 3 8 4.79 8 7s1.79 4 4 4zM6 21v-1a4 4 0 014-4h4a4 4 0 014 4v1" /></svg>
                    </button>
                </div> */}
    </header>
  );
}
