import { useCallback, useEffect, useRef, useState } from "react";
import { fetchPriceFromUniswap } from "~~/utils/scaffold-eth/fetchPriceFromUniswap";

type CacheEntry = { price: number; ts: number };
const priceCache = new Map<string, CacheEntry>();

export function useUniswapPrice(opts: {
  targetNetwork: any;
  stableAddress: string;
  intervalMs?: number;
  ttlMs?: number;
}) {
  const { targetNetwork, stableAddress, intervalMs = 15000, ttlMs = 15000 } = opts;
  const cacheKey = `${targetNetwork?.chainId ?? "0"}:${stableAddress ?? "0"}`;

  const [price, setPrice] = useState<number | null>(() => {
    const cached = priceCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < ttlMs) return cached.price;
    return null;
  });
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const intervalRef = useRef<number | null>(null);
  const mountedRef = useRef(true);
  const visibleRef = useRef(typeof document !== "undefined" ? !document.hidden : true);

  useEffect(() => {
    const onVis = () => {
      visibleRef.current = !document.hidden;
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, []);

  const doFetch = useCallback(
    async (showLoading = false) => {
      try {
        const cached = priceCache.get(cacheKey);
        if (cached && Date.now() - cached.ts < ttlMs) {
          setPrice(cached.price);
          return cached.price;
        }

        if (showLoading) setIsLoading(true);
        const fetched = await fetchPriceFromUniswap(targetNetwork, stableAddress);
        if (!mountedRef.current) return null;
        if (typeof fetched === "number" && fetched > 0) {
          priceCache.set(cacheKey, { price: fetched, ts: Date.now() });
          setPrice(fetched);
        }
        setError(null);
        return fetched;
      } catch (err: any) {
        if (!mountedRef.current) return null;
        const e = err instanceof Error ? err : new Error(String(err));
        setError(e);
        throw e;
      } finally {
        if (showLoading) setIsLoading(false);
      }
    },
    [cacheKey, targetNetwork, stableAddress, ttlMs],
  );

  useEffect(() => {
    mountedRef.current = true;

    // initial fetch + polling
    const start = async () => {
      try {
        await doFetch(true);
      } catch {
        // ignore fetch errors on initial load
      }

      intervalRef.current = window.setInterval(async () => {
        if (!mountedRef.current) return;
        if (!visibleRef.current) return;
        try {
          await doFetch(false);
        } catch {
          // ignore periodic fetch errors
        }
      }, intervalMs) as unknown as number;
    };

    start();

    return () => {
      mountedRef.current = false;
      if (intervalRef.current) {
        window.clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [doFetch, intervalMs]);

  const refresh = useCallback(async () => doFetch(true), [doFetch]);

  return { price, isLoading, error, refresh };
}

export default useUniswapPrice;
