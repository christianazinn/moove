// One-time eBay seller setup for the listing agent (#32). Run from agents/:
//   npm run ebay:setup -- consent              print the URL to sign in as the sandbox test seller
//   npm run ebay:setup -- token <code|url>     exchange the consent code for a refresh token
//   npm run ebay:setup -- provision            opt in to business policies, create 3 policies + location
//   npm run ebay:setup -- check                verify every key and preview category picks
// Each step prints the lines to paste into .env.local. Nothing is written for you.
import '../src/config.js'; // loads .env.local
import {
  USER_SCOPES,
  ebayCall,
  ebayEnv,
  missingEbayKeys,
  oauthToken,
  pickLeaf,
} from '../src/integrations/ebay.js';

const env = (k: string) => process.env[k] ?? '';
const need = (...keys: string[]) => {
  const missing = keys.filter(k => !env(k));
  if (missing.length) {
    console.error(`Set ${missing.join(', ')} in .env.local first.`);
    process.exit(1);
  }
};
const authHost = () => (ebayEnv.production ? 'https://auth.ebay.com' : 'https://auth.sandbox.ebay.com');
const CATEGORY_TYPES = [{ name: 'ALL_EXCLUDING_MOTORS_VEHICLES' }];
const NAME = 'Moove';

async function consent() {
  need('EBAY_CLIENT_ID', 'EBAY_RUNAME');
  const q = new URLSearchParams({ client_id: env('EBAY_CLIENT_ID'), redirect_uri: env('EBAY_RUNAME'), response_type: 'code', scope: USER_SCOPES.join(' ') });
  console.log(`Open this, sign in as your ${ebayEnv.production ? '' : 'sandbox TESTUSER_ '}seller, and accept:\n\n${authHost()}/oauth2/authorize?${q}\n`);
  console.log('You land on your Accept URL. Within 5 minutes, copy the whole address and run:\n  npm run ebay:setup -- token "<that URL>"');
}

async function token(arg: string | undefined) {
  need('EBAY_CLIENT_ID', 'EBAY_CLIENT_SECRET', 'EBAY_RUNAME');
  if (!arg) throw new Error('pass the code or the full redirect URL');
  const code = arg.includes('code=') ? new URL(arg.startsWith('http') ? arg : `https://x/?${arg}`).searchParams.get('code')! : decodeURIComponent(arg);
  const t = await oauthToken({ grant_type: 'authorization_code', code, redirect_uri: env('EBAY_RUNAME') });
  const days = Math.round((t.refresh_token_expires_in ?? 0) / 86400);
  console.log(`Got a refresh token (valid ~${days} days). Add to .env.local:\n\nEBAY_REFRESH_TOKEN=${t.refresh_token}\n\nThen run: npm run ebay:setup -- provision`);
}

type Policy = { name: string } & Record<string, string>;
async function findOrCreate(kind: 'fulfillment' | 'payment' | 'return', idField: string, body: object): Promise<string> {
  const list = await ebayCall<Record<string, Policy[]>>('GET', `/sell/account/v1/${kind}_policy?marketplace_id=${ebayEnv.marketplaceId}`);
  const found = Object.values(list).flat().find(p => p && typeof p === 'object' && p.name === `${NAME} ${kind}`);
  if (found) return found[idField];
  const created = await ebayCall<Record<string, string>>('POST', `/sell/account/v1/${kind}_policy${kind === 'fulfillment' ? '/' : ''}`, {
    body: { name: `${NAME} ${kind}`, marketplaceId: ebayEnv.marketplaceId, categoryTypes: CATEGORY_TYPES, ...body },
  });
  return created[idField];
}

async function provision() {
  need('EBAY_CLIENT_ID', 'EBAY_CLIENT_SECRET', 'EBAY_REFRESH_TOKEN');
  // Sandbox Seller Hub redirects to production, so the opt-in has to happen by API. 409 = already in.
  await ebayCall('POST', '/sell/account/v1/program/opt_in', { body: { programType: 'SELLING_POLICY_MANAGEMENT' }, okStatuses: [409] });
  console.log('Opted in to business policies (eBay can take a while to apply this; rerun if policy creation fails).');

  const fulfillment = await findOrCreate('fulfillment', 'fulfillmentPolicyId', {
    handlingTime: { unit: 'DAY', value: 2 },
    localPickup: true,
    // Flat rate avoids the "invalid ShippingPackage" publish error people hit with calculated shipping.
    shippingOptions: [
      {
        optionType: 'DOMESTIC',
        costType: 'FLAT_RATE',
        shippingServices: [{ sortOrder: 1, shippingCarrierCode: 'USPS', shippingServiceCode: 'USPSPriority', shippingCost: { value: '15.00', currency: 'USD' } }],
      },
    ],
  });
  const payment = await findOrCreate('payment', 'paymentPolicyId', { immediatePay: true });
  const ret = await findOrCreate('return', 'returnPolicyId', { returnsAccepted: false });

  const locationKey = env('EBAY_LOCATION_KEY') || 'moove-sf';
  await ebayCall('POST', `/sell/inventory/v1/location/${locationKey}`, {
    body: {
      name: 'Moove',
      locationTypes: ['WAREHOUSE'],
      merchantLocationStatus: 'ENABLED',
      location: { address: { city: 'San Francisco', stateOrProvince: 'CA', postalCode: '94103', country: 'US' } },
    },
    okStatuses: [409], // already exists
  });

  console.log(`\nAdd to .env.local:\n\nEBAY_FULFILLMENT_POLICY_ID=${fulfillment}\nEBAY_PAYMENT_POLICY_ID=${payment}\nEBAY_RETURN_POLICY_ID=${ret}\nEBAY_LOCATION_KEY=${locationKey}\n\nThen run: npm run ebay:setup -- check`);
}

async function check() {
  const missing = missingEbayKeys();
  console.log(missing.length ? `Missing: ${missing.join(', ')} (the worker will simulate posts)` : `All keys set: the worker will post to eBay ${ebayEnv.production ? 'PRODUCTION' : 'sandbox'}.`);
  need('EBAY_CLIENT_ID', 'EBAY_CLIENT_SECRET');
  const { categoryTreeId } = await ebayCall<{ categoryTreeId: string }>('GET', `/commerce/taxonomy/v1/get_default_category_tree_id?marketplace_id=${ebayEnv.marketplaceId}`, { token: 'app' });
  console.log(`App token OK, category tree ${categoryTreeId}`);
  if (env('EBAY_REFRESH_TOKEN')) {
    const programs = await ebayCall<{ programs?: { programType: string }[] }>('GET', '/sell/account/v1/program/get_opted_in_programs');
    console.log(`User token OK, opted in: ${(programs.programs ?? []).map(p => p.programType).join(', ') || 'none yet'}`);
  }
  const { categorySubtreeNode } = await ebayCall<{ categorySubtreeNode: Node }>('GET', `/commerce/taxonomy/v1/category_tree/${categoryTreeId}/get_category_subtree?category_id=3197`, { token: 'app' });
  const leaves: { id: string; name: string; path: string }[] = [];
  type Node = { category: { categoryId: string; categoryName: string }; leafCategoryTreeNode?: boolean; childCategoryTreeNodes?: Node[] };
  const walk = (n: Node, p: string) => {
    const path = p ? `${p} > ${n.category.categoryName}` : n.category.categoryName;
    if (n.leafCategoryTreeNode) leaves.push({ id: n.category.categoryId, name: n.category.categoryName, path });
    (n.childCategoryTreeNodes ?? []).forEach(c => walk(c, path));
  };
  walk(categorySubtreeNode, '');
  for (const [cat, name] of [['chair', 'Office chair'], ['table', 'Desk'], ['sofa', 'Bean bag'], ['storage', 'Bookshelf']]) {
    const l = pickLeaf(leaves, cat, name);
    console.log(`  ${name} -> ${l.path} (#${l.id})`);
  }
}

const [cmd, arg] = process.argv.slice(2);
const steps: Record<string, () => Promise<void>> = { consent, token: () => token(arg), provision, check };
if (!steps[cmd]) {
  console.log('Usage: npm run ebay:setup -- consent | token <code|url> | provision | check');
  process.exit(1);
}
steps[cmd]().catch(err => {
  console.error(String(err));
  process.exit(1);
});
