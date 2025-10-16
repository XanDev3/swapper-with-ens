"use client";

import type { NextPage } from "next";
import SwapCard from "~~/components/SwapCard";
import SwapHeader from "~~/components/SwapHeader";

const Home: NextPage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-900 via-purple-800 to-pink-700 text-white">
      <SwapHeader />

      <main className="py-8 px-4 sm:px-8 flex flex-col items-center">
        <div className="w-full max-w-2xl">
          <SwapCard />
        </div>

        <div className="mt-8 text-center text-sm text-gray-200">
          <p>
            Built with{" "}
            <a href="https://docs.scaffoldeth.io" target="_blank" rel="noreferrer" className="underline">
              Scaffold-Eth
            </a>{" "}
            and SwapStables.sol • Swap for more ETH with Uniswap v2
          </p>
        </div>
      </main>
    </div>
  );
};

export default Home;
