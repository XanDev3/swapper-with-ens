"use client";

import { useEffect, useState } from "react";
import type { NextPage } from "next";
import { useTheme } from "next-themes";
import SwapCard from "~~/components/SwapCard";
import SwapHeader from "~~/components/SwapHeader";

const Home: NextPage = () => {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const themedClassName =
    mounted && resolvedTheme === "light"
      ? "min-h-screen bg-gradient-to-b from-pink-700 via-purple-800 to-indigo-900 text-white"
      : "min-h-screen bg-gradient-to-b from-indigo-900 via-purple-800 to-pink-700 text-white";

  return (
    <div className={themedClassName}>
      <SwapHeader />
      <main className="py-8 px-4 sm:px-8 flex flex-col items-center">
        <div className="w-full max-w-2xl">
          <SwapCard />
        </div>
        <div className="mt-8 text-center text-sm text-gray-200">
          <p>
            Built with{" "}
            <a href="https://docs.scaffoldeth.io" target="_blank" rel="noreferrer" className="underline">
              Scaffold-ETH
            </a>{" "}
            and SwapStables.sol • Swap for more ETH with Uniswap v2
          </p>
        </div>
      </main>
    </div>
  );
};

export default Home;
