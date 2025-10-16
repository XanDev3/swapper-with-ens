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
          <span className="text-white font-semibold">$</span>
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
            </nav>
          </li>
        </ul>
      </details>

      {/* Display links horizontally if on large screen */}
      <nav className="hidden lg:flex gap-3 text-sm text-neutral">
        <a className="hover:text-gray-200" href="#">
          Docs
        </a>
      </nav>
    </header>
  );
}
