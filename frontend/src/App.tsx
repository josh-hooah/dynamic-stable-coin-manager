import { useMemo, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeAbiParameters,
  fallback,
  http,
  keccak256,
  parseAbiParameters
} from "viem";
import type { Hex } from "viem";

import controllerAbi from "@shared/abi/StablePolicyController.json";
import hookAbi from "@shared/abi/DynamicStableManagerHook.json";
import mockManagerAbi from "@shared/abi/MockPoolManager.json";
import { DEFAULT_POLICY, REGIME_LABELS, REASON_LABELS } from "@shared/constants/policy";

const DYNAMIC_FEE_FLAG = 0x800000;

declare global {
  interface Window {
    ethereum?: {
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
    };
  }
}

type Preview = {
  regime: number;
  reasonCode: number;
  deviationTicks: number;
  selectedFeeBps: number;
  estimatedImpactBps: number;
  maxSwap: bigint;
  maxImpactBps: number;
  wouldRevert: boolean;
  dynamicFeeOverrideEnabled: boolean;
};

export function App() {
  const [rpcUrl, setRpcUrl] = useState("http://127.0.0.1:8545");
  const [poolManager, setPoolManager] = useState<Hex>("0x0000000000000000000000000000000000000000");
  const [controller, setController] = useState<Hex>("0x0000000000000000000000000000000000000000");
  const [hook, setHook] = useState<Hex>("0x0000000000000000000000000000000000000000");
  const [token0, setToken0] = useState<Hex>("0x0000000000000000000000000000000000001000");
  const [token1, setToken1] = useState<Hex>("0x0000000000000000000000000000000000002000");
  const [account, setAccount] = useState<Hex | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [status, setStatus] = useState<string>("Idle");

  const publicClient = useMemo(
    () =>
      createPublicClient({
        transport: fallback([http(rpcUrl)])
      }),
    [rpcUrl]
  );

  const poolKey = useMemo(
    () => ({
      currency0: token0,
      currency1: token1,
      fee: DYNAMIC_FEE_FLAG,
      tickSpacing: 1,
      hooks: hook
    }),
    [token0, token1, hook]
  );

  const poolId = useMemo(() => {
    return keccak256(
      encodeAbiParameters(
        parseAbiParameters("(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"),
        [poolKey]
      )
    );
  }, [poolKey]);

  async function connectWallet() {
    if (!window.ethereum) {
      setStatus("No injected wallet found");
      return;
    }

    const addresses = (await window.ethereum.request({ method: "eth_requestAccounts" })) as Hex[];
    setAccount(addresses[0]);
    setStatus(`Connected ${addresses[0]}`);
  }

  async function applyPolicy() {
    if (!account || !window.ethereum) {
      setStatus("Connect wallet first");
      return;
    }

    const wallet = createWalletClient({ account, transport: custom(window.ethereum) });

    setStatus("Submitting setPoolConfig transaction...");

    const hash = await wallet.writeContract({
      address: controller,
      abi: controllerAbi,
      functionName: "setPoolConfig",
      args: [poolId, { ...DEFAULT_POLICY, admin: account, lastUpdatedAt: 0 }]
    });

    setStatus(`Config tx submitted: ${hash}`);
  }

  async function fetchPreview() {
    const response = (await publicClient.readContract({
      address: hook,
      abi: hookAbi,
      functionName: "previewSwapPolicy",
      args: [poolKey, { zeroForOne: true, amountSpecified: -100_000_000n, sqrtPriceLimitX96: 999500000000000000n }]
    })) as Preview;

    setPreview(response);
    setStatus("Preview refreshed");
  }

  async function runNormalDemo() {
    if (!account || !window.ethereum) {
      setStatus("Connect wallet first");
      return;
    }

    const wallet = createWalletClient({ account, transport: custom(window.ethereum) });

    await wallet.writeContract({
      address: poolManager,
      abi: mockManagerAbi,
      functionName: "setSlot0",
      args: [poolId, 1000000000000000000n, 5, 0, 0]
    });

    await fetchPreview();
    setStatus("Normal regime demo executed");
  }

  async function runStressDemo() {
    if (!account || !window.ethereum) {
      setStatus("Connect wallet first");
      return;
    }

    const wallet = createWalletClient({ account, transport: custom(window.ethereum) });

    await wallet.writeContract({
      address: poolManager,
      abi: mockManagerAbi,
      functionName: "setSlot0",
      args: [poolId, 1000000000000000000n, 35, 0, 0]
    });

    await fetchPreview();
    setStatus("Depeg stress demo executed");
  }

  return (
    <main className="app-shell">
      <header className="hero">
        <p className="kicker">Dynamic Stablecoin Manager</p>
        <h1>Adaptive Fees + Deterministic Peg Defense</h1>
        <p>
          Uniswap v4 stable pool policy console. No keepers, no reactive automation, only deterministic on-chain regime
          logic.
        </p>
      </header>

      <section className="panel">
        <h2>Connection</h2>
        <div className="grid">
          <label>
            RPC URL
            <input value={rpcUrl} onChange={(event) => setRpcUrl(event.target.value)} />
          </label>
          <button onClick={connectWallet}>{account ? "Wallet Connected" : "Connect Wallet"}</button>
        </div>
      </section>

      <section className="panel">
        <h2>Addresses</h2>
        <div className="grid">
          <label>
            PoolManager
            <input value={poolManager} onChange={(event) => setPoolManager(event.target.value as Hex)} />
          </label>
          <label>
            Controller
            <input value={controller} onChange={(event) => setController(event.target.value as Hex)} />
          </label>
          <label>
            Hook
            <input value={hook} onChange={(event) => setHook(event.target.value as Hex)} />
          </label>
          <label>
            Token0
            <input value={token0} onChange={(event) => setToken0(event.target.value as Hex)} />
          </label>
          <label>
            Token1
            <input value={token1} onChange={(event) => setToken1(event.target.value as Hex)} />
          </label>
        </div>
        <p className="mono">PoolId: {poolId}</p>
      </section>

      <section className="panel controls">
        <h2>Policy Actions</h2>
        <button onClick={applyPolicy}>Configure Peg Bands + Fee Policy</button>
        <button onClick={runNormalDemo}>Run Normal Regime Demo</button>
        <button onClick={runStressDemo}>Run Depeg Stress Demo</button>
        <button onClick={fetchPreview}>Refresh Effective Regime</button>
      </section>

      <section className="panel">
        <h2>Live Policy Preview</h2>
        {preview ? (
          <div className="stats">
            <div>
              <span>Regime</span>
              <strong>{REGIME_LABELS[preview.regime]}</strong>
            </div>
            <div>
              <span>Reason</span>
              <strong>{REASON_LABELS[preview.reasonCode]}</strong>
            </div>
            <div>
              <span>Effective Fee</span>
              <strong>{preview.selectedFeeBps} bps</strong>
            </div>
            <div>
              <span>Deviation</span>
              <strong>{preview.deviationTicks} ticks</strong>
            </div>
            <div>
              <span>Max Swap</span>
              <strong>{preview.maxSwap.toString()}</strong>
            </div>
            <div>
              <span>Max Impact</span>
              <strong>{preview.maxImpactBps} bps</strong>
            </div>
            <div>
              <span>Est. Impact</span>
              <strong>{preview.estimatedImpactBps} bps</strong>
            </div>
            <div>
              <span>Would Revert</span>
              <strong>{preview.wouldRevert ? "Yes" : "No"}</strong>
            </div>
          </div>
        ) : (
          <p>No preview fetched yet.</p>
        )}
      </section>

      <footer className="status mono">{status}</footer>
    </main>
  );
}
