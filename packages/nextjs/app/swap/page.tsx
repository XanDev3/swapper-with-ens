"use client";

import React from "react";
import SwapCard from "../../components/SwapCard";
import SwapHeader from "../../components/SwapHeader";

export default function SwapPage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-900 via-purple-800 to-pink-700 text-white">
      <SwapHeader />

      <main className="py-8 px-4 sm:px-8 flex flex-col items-center">
        <div className="w-full max-w-2xl">
          <SwapCard />
        </div>

        <div className="mt-8 text-center text-sm text-gray-200">
          <p>Built with SwapStables • Uniswap v2 profit-maximizing swaps</p>
        </div>
      </main>
    </div>
  );
}
