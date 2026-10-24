// Prints the agents' x402 wallet (Base Sepolia), tops it up from the CDP faucet, and shows balances.
// Usage: npm run x402:wallet [-- --faucet]
import "./env.js";
import { CdpClient } from "@coinbase/cdp-sdk";
import { CdpX402Client } from "@coinbase/cdp-sdk/x402";
import { BASE_SEPOLIA, hasCdpKeys, USDC_BASE_SEPOLIA } from "../src/integrations/x402.js";

if (!hasCdpKeys(process.env)) {
  console.error("Set CDP_API_KEY_ID, CDP_API_KEY_SECRET and CDP_WALLET_SECRET in .env.local first.");
  process.exit(1);
}

// Same account name as createX402Rail, so this is the wallet the agents pay from.
// This client never pays; the zero cap just keeps the SDK from warning about missing spend controls.
const buyer = new CdpX402Client({
  environment: "development",
  walletConfig: { type: "eoa", accountName: "moove-agents" },
  spendControls: { maxAmountPerPayment: { atomic: 0n, asset: USDC_BASE_SEPOLIA }, allowedNetworks: [BASE_SEPOLIA] },
});
const { evmAddress } = await buyer.getAddresses();
console.log(`Agent wallet (Base Sepolia): ${evmAddress}`);
console.log(`Explorer: https://sepolia.basescan.org/address/${evmAddress}`);

const cdp = new CdpClient();
const faucet = process.argv.includes("--faucet");
if (faucet) {
  const { transactionHash } = await cdp.evm.requestFaucet({ address: evmAddress, network: "base-sepolia", token: "usdc" });
  console.log(`Faucet USDC tx: https://sepolia.basescan.org/tx/${transactionHash}`);
}

const { balances } = await cdp.evm.listTokenBalances({ address: evmAddress, network: "base-sepolia" });
for (const b of balances) {
  const { amount, decimals } = b.amount as { amount: bigint; decimals: number };
  console.log(`  ${b.token.symbol ?? b.token.contractAddress}: ${Number(amount) / 10 ** decimals}`);
}
if (balances.length === 0) console.log(faucet ? "  (faucet tx not confirmed yet; rerun in ~10s)" : "  (empty: run with -- --faucet)");
