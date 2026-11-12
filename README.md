# Morpho contracts on Zenith EVM testnet

Deployment of the open-source [Morpho](https://github.com/morpho-org) lending stack (Morpho core + Vault V2) on **Zenith EVM testnet**, plus a demo zUSD/zETH market and vault.

User-facing, this deployment is branded **ZLP — Zenith Lending Protocol** (e.g. the vault is named "ZLP zUSD Vault", symbol `zlpUSD`). **This deployment or ZLP is not affiliated with or endorsed by Morpho**; **it runs Morpho's unmodified open-source contracts.**

All contracts below are deployed and **source-verified** on the [Zenith testnet explorer](https://explorer.testnet.zenith.network/).

## Network

| | |
|---|---|
| RPC | `https://rpc.testnet.zenith.network/` |
| Chain ID | `936485` |
| Explorer | https://explorer.testnet.zenith.network/ |
| Gas token | ZTH ([faucet](https://explorer.testnet.zenith.network/faucet)) |

## Deployed contracts

Core protocol (`deploy.sh`):

| Contract | Address |
|---|---|
| Morpho (core) | `0x31C6408EfC0e4c375826f5A02e159C57dab7d72F` |
| AdaptiveCurveIrm | `0x062a8f404d78329E88923C7587A44BD27f9b6AC4` |
| PreLiquidationFactory | `0xB2C6b066C5E4738A936CAdAe1054B0772Fdec01C` |
| VaultV2Factory | `0xDe44D35fcEB5BF5B470cf8f54Ea45d5f2deA3c11` |
| MorphoMarketV1AdapterV2Factory | `0xc243f72D1bab8fb15c8206330929F5b0b9E8f100` |

Enabled on Morpho: IRM `AdaptiveCurveIrm`; LLTVs 77%, 86%, 91.5%, 94.5%.

Demo (`demo/script/Setup.s.sol`):

| Contract | Address |
|---|---|
| zUSD — Zenith Test Dollar (6 decimals) | `0x94f56A17f02D8246301eb206B2fc5579a266aF05` |
| zETH — Zenith Test Ether (18 decimals) | `0x2914e9FEC92f9DF44797969682656a4166a2E46E` |
| FixedPriceOracle (1 zETH = 2,000 zUSD) | `0xbdAAA4A475F6197f8AeD0dA9839DA92A6D0fB79D` |
| ZLP zUSD Vault (VaultV2, `zlpUSD`) | `0xa701b9260354F9721D9454C44Fe0e37c6b825636` |
| Vault adapter (MorphoMarketV1AdapterV2) | `0x64287b133132a2dA64Cc52D06b10B28e98011116` |

Market zETH → zUSD, 86% LLTV, id `0xf76fc23d58807765a2d4d70c1d5078e07c59bacc3e8f472e2df057823fd77d2e`.

Deployer / owner of everything: `0xbC9daFF1E2C4Ae3776513009FB725bC9c46066B8` (Morpho owner; vault owner, curator and allocator; token minter; oracle owner).

All addresses are also in [`deployments.env`](./deployments.env).

> Testnet only. The test tokens are freely mintable by the deployer and the oracle price is set by hand, so do not treat any of this as having value.

## Repository layout

| Path | What |
|---|---|
| `morpho-blue/` | Submodule: [morpho-org/morpho-blue](https://github.com/morpho-org/morpho-blue) @ `430bd61` |
| `vault-v2/` | Submodule: [morpho-org/vault-v2](https://github.com/morpho-org/vault-v2) @ `ec22379a` |
| `deploy.sh` | Deploys the core contracts and enables the IRM and LLTVs |
| `demo/` | Foundry project: `TestToken`, `FixedPriceOracle`, `script/Setup.s.sol` (one-time: tokens, oracle, market, vault), `script/Demo1Borrow.s.sol`, `Demo2MarginCall.s.sol`, `Demo3aRepay.s.sol`, `Demo3bLiquidate.s.sol` (the demos, sharing `DemoBase.sol`) |
| `demo.sh` | Runs the demos: `./demo.sh borrow`, `margin-call`, then `repay` or `liquidate` |
| `demo/broadcast/` | Transaction records of the setup and demo runs |
| `verify.sh` | Publishes the source of all deployed contracts on the explorer |
| `deployments.env` | Deployed addresses |
| `deploy.log`, `demo-setup.log` | Output of the deployment runs |

## Usage

Requires [Foundry](https://getfoundry.sh/).

```sh
git clone --recurse-submodules https://github.com/vadasnorbert/morpho-contracts-on-zenith
cd morpho-contracts-on-zenith
cp .env.example .env   # fill in DEPLOYER_ADDRESS / DEPLOYER_ACCOUNT
```

Signing uses an encrypted Foundry keystore, never a plaintext key:

```sh
cast wallet import zenith-deployer --interactive
```

Deploy the core contracts (prompts for the keystore password; set `KEYSTORE_PASSWORD_FILE` to skip prompts):

```sh
./deploy.sh
```

Create the demo tokens, oracle, market and vault (one-time, already done on testnet; the [demos](#demos) below build on it):

```sh
set -a; . ./.env; . ./deployments.env; set +a
cd demo
forge script script/Setup.s.sol --rpc-url "$ZENITH_RPC_URL" --broadcast \
  --account "$DEPLOYER_ACCOUNT" --sender "$DEPLOYER_ADDRESS"
```

Verify sources on the explorer (no signing needed):

```sh
./verify.sh
```

### Changing the oracle price

```sh
# price = loan units per collateral unit, scaled by 1e36. 2,000 zUSD/zETH = 2000e24
cast send 0xbdAAA4A475F6197f8AeD0dA9839DA92A6D0fB79D "setPrice(uint256)" 1500000000000000000000000000 \
  --rpc-url "$ZENITH_RPC_URL" --account "$DEPLOYER_ACCOUNT" --priority-gas-price 1gwei
```

> **Gas tip:** the Zenith testnet RPC currently suggests a 500–600 gwei priority fee although the base fee is 7 wei and blocks are nearly empty. Pass `--priority-gas-price 1gwei` (and `--with-gas-price 2gwei` for `forge script`), otherwise transactions cost ~600x more than needed.

## Demos

Four demos on the zETH/zUSD market, one loan's life from start to finish. Run them in order: **1 → 2 → 3a or 3b**. Both endings close the position and restore the price, so you can start again with demo 1.

| | Command | What happens | Ends with |
|---|---|---|---|
| **1 — borrow** | `./demo.sh borrow` | Sets the price to 2,000 zUSD/zETH. The lender (deployer) deposits 20,000 zUSD into the **ZLP zUSD Vault**, which supplies it to the market. The borrower posts 10 zETH and borrows 10,000 zUSD (~50% LTV). | An open loan, well under the 86% LLTV |
| **2 — margin call** | `./demo.sh margin-call` | The deployer drops the price until the loan sits at 80% LTV. Prints the margin call: LTV, the liquidation price, and how much zUSD to repay or zETH to add to get back to 50% LTV. | A loan close to liquidation |
| **3a — repayment** | `./demo.sh repay` | The borrower answers the margin call: repays the whole debt plus interest and withdraws all collateral. The deployer restores the price to 2,000. | Closed position, borrower keeps the collateral |
| **3b — liquidation** | `./demo.sh liquidate` | The borrower ignores the margin call: the deployer drops the price further, to 95% LTV (above the 86% LLTV). The liquidator repays the whole debt and seizes zETH at a ~4.4% discount. The deployer restores the price to 2,000. | Closed position, collateral seized |

Morpho has no on-chain margin call: like in traditional finance it is an alert (from a lender, a monitoring service or a front end) that a loan is close to liquidation. Demo 2 prints that alert from the on-chain numbers. Each demo refuses to run out of order ("run demo 1 (borrow) first"), and prints the borrower's position, market totals and vault assets before and after. Demo 3b also works straight after demo 1.

**Wallets.** The demos sign with encrypted Foundry keystores named in `.env`:

| Role | `.env` | Needs |
|---|---|---|
| Deployer: lender, oracle owner, token minter | `DEPLOYER_ADDRESS`, `DEPLOYER_ACCOUNT` | The deployer keystore (only the deployer can mint test tokens and set the price) |
| Borrower | `BORROWER`, `BORROWER_ACCOUNT` (optional) | Defaults to the deployer. A separate borrower gets zETH and ZTH for gas from the deployer |
| Liquidator | `LIQUIDATOR`, `LIQUIDATOR_ACCOUNT` | Create once: `cast wallet new zenith-liquidator`. Gets zUSD and ZTH for gas from the deployer |

`demo.sh` asks for each keystore's password once per run. Extra arguments go to `forge`, e.g. `./demo.sh borrow --rpc-url http://127.0.0.1:8545` against a local `anvil --fork-url` copy of the testnet.

Optional env: demo 1 — `LEND_ZUSD` (20000), `COLLATERAL_ZETH` (10), `BORROW_ZUSD` (10000), `PRICE_USD` (2000); demo 2 — `MARGIN_LTV_BPS` (8000), `SAFE_LTV_BPS` (5000); demo 3a — `RESTORE_PRICE_USD` (2000); demo 3b — `CRASH_PRICE_USD` (default: price giving 95% LTV), `RESTORE_PRICE_USD` (2000).

> `demo.sh` caps the tip at 1 gwei (see the gas note above) and doubles gas estimates: forge estimates in a simulation where no time has passed, and interest accrual costs more gas once time has passed on chain.

### Run on testnet: borrow → margin call → repayment (12 Nov 2026)

| Step | Result | Tx |
|---|---|---|
| 1: lend | 20,000 zUSD deposited into the ZLP zUSD Vault (vault total 140,000 zUSD) | [`0x7fa2e42c…`](https://explorer.testnet.zenith.network/transactions/0x7fa2e42caba3d869b503919785e0f2bbfaf6a23bd9e8cd605cf5b5504536a16a) |
| 1: collateral | 10 zETH posted (10.09 zETH incl. leftover from earlier runs) | [`0xc21d48ef…`](https://explorer.testnet.zenith.network/transactions/0xc21d48ef11cecfa917c0fc725859f732c588ad570d0dc6ba35604a99b8e9e982) |
| 1: borrow | 10,000 zUSD borrowed, 49.56% LTV | [`0x62331fc7…`](https://explorer.testnet.zenith.network/transactions/0x62331fc7ee9c7037833a95e25a2a00ce305488f31202883169092c310174d981) |
| 2: margin call | Price 2,000 → 1,239.12 zUSD/zETH, loan at 80.00% LTV. Liquidation price 1,152.67 (6.97% lower); repay 3,750 zUSD or add 6.05 zETH to get back to 50% | [`0x4346878a…`](https://explorer.testnet.zenith.network/transactions/0x4346878addcb071362c4e16b26f65fe4048fc25bc0fa809bda3d9b28f43eabbf) |
| 3a: repay | 10,000.000727 zUSD repaid (principal + interest), debt cleared | [`0xaa59978e…`](https://explorer.testnet.zenith.network/transactions/0xaa59978e2e3e13d68b5ba94134f33bd807e6a4f88307ddae31b7434b40e321bf) |
| 3a: withdraw | All 10.0878 zETH collateral returned to the borrower | [`0x8aea1e11…`](https://explorer.testnet.zenith.network/transactions/0x8aea1e11e36d9ff14300d8137e5e0e8ecd8a095fcc1bec7474368cbfca510134) |
| 3a: restore | Price back to 2,000; position fully closed | [`0xf6ca68a6…`](https://explorer.testnet.zenith.network/transactions/0xf6ca68a630470143abe32e164aa16fa943ccc146fa044833cb086225f78d1119) |

Gas: 0.0004 ZTH (demo 1), 0.00003 ZTH (demo 2), 0.0002 ZTH (demo 3a). Records: `demo/broadcast/Demo1Borrow.s.sol/`, `Demo2MarginCall.s.sol/`, `Demo3aRepay.s.sol/`.

### Run on testnet: borrow → margin call → liquidation (12 Nov 2026)

| Step | Result | Tx |
|---|---|---|
| 1: lend | 20,000 zUSD deposited into the ZLP zUSD Vault (vault total 160,000 zUSD) | [`0x0c368ea2…`](https://explorer.testnet.zenith.network/transactions/0x0c368ea252a53ad6f8243156f37d3882c79d1d31a89319da2fe944c3cbab87a3) |
| 1: collateral | 10 zETH posted | [`0xab657566…`](https://explorer.testnet.zenith.network/transactions/0xab65756619377f492ddc73f758b7365f27c00f8594a682e2cedd20832c35c20e) |
| 1: borrow | 10,000 zUSD borrowed, 50.00% LTV | [`0x03ab0b11…`](https://explorer.testnet.zenith.network/transactions/0x03ab0b11d847dc536985998c7155048086bd06e6d0e24968d3dcb4f5fa195cbe) |
| 2: margin call | Price 2,000 → 1,250 zUSD/zETH, loan at 80.00% LTV. Liquidation price 1,162.79 (6.97% lower); repay 3,750 zUSD or add 6 zETH to get back to 50% | [`0x2e933e9a…`](https://explorer.testnet.zenith.network/transactions/0x2e933e9a71d0e6b095e6837c6b709a18d4c49b9d758afe5050aea3d48c9017f9) |
| 3b: price drop | Borrower did not respond; price 1,250 → 1,052.63, loan at 95.00% LTV | [`0xc84fce66…`](https://explorer.testnet.zenith.network/transactions/0xc84fce66a29c78874f09dd25b985dfe47362cfd722e1734002ff75d277d98050) |
| 3b: liquidate | Liquidator repaid 10,000.00011 zUSD, seized 9.9165 zETH (10,438.41 zUSD at 1,052.63, +4.38%); no bad debt | [`0xd13aadad…`](https://explorer.testnet.zenith.network/transactions/0xd13aadad83d09c5ab092861d5b49fb623e43b81da06375f429917d63ce324bf7) |
| 3b: restore | Price back to 2,000; borrower left with 0 debt and 0.0835 zETH | [`0x42c3e98b…`](https://explorer.testnet.zenith.network/transactions/0x42c3e98bde9cfb4a3f100f3142f9912aa54a467da04c3c01ddea75284fcddafa) |

Gas: 0.0004 ZTH (demo 1), 0.00003 ZTH (demo 2), 0.0002 ZTH (demo 3b). Records: `demo/broadcast/Demo1Borrow.s.sol/`, `Demo2MarginCall.s.sol/`, `Demo3bLiquidate.s.sol/` (the `run-latest.json` files hold this run; the repayment path's runs are kept by timestamp).

### Earlier two-demo run on testnet (12 Nov 2026)

Before the margin call and repayment demos existed, borrow and liquidation ran as "demo 1" and "demo 2" (`Demo2Liquidate.s.sol`, now `Demo3bLiquidate.s.sol`):

| Step | Result | Tx |
|---|---|---|
| Demo 1: lend | 20,000 zUSD deposited into the ZLP zUSD Vault (vault total 120,000 zUSD) | [`0xc4b35f09…`](https://explorer.testnet.zenith.network/transactions/0xc4b35f09e998ee65be83352922fa853aa13378077665dc145aaa32b2f2bb68ca) |
| Demo 1: collateral | 10 zETH posted (10.51 zETH incl. leftover from the first liquidation) | [`0x936724d9…`](https://explorer.testnet.zenith.network/transactions/0x936724d906a127f37f0af3a344fa249794d0cb60bcf1a3f3dcfa23ee117ae4a2) |
| Demo 1: borrow | 10,000 zUSD borrowed, 47.6% LTV | [`0x742effd3…`](https://explorer.testnet.zenith.network/transactions/0x742effd375403a6cf97c8803d9bb2c27e0f7be0dde6b2489bb7351817700753e) |
| Demo 2: price drop | 2,000 → 1,001 zUSD/zETH, position at 95% LTV | [`0x3037933c…`](https://explorer.testnet.zenith.network/transactions/0x3037933ca9facbfe618aa0321ad0048c5695b5eba95a3d9acd590dd69e86eeda) |
| Demo 2: liquidate | Liquidator repaid 10,000.0005 zUSD, seized 10.4228 zETH (10,438.41 zUSD at 1,001, +4.38%) | [`0x0483f8b7…`](https://explorer.testnet.zenith.network/transactions/0x0483f8b76148397098047a635cdd51e2c86282eb3f5968fe592c53e599b85902) |
| Demo 2: restore | Price back to 2,000; borrower left with 0 debt and 0.0878 zETH | [`0x560c1b26…`](https://explorer.testnet.zenith.network/transactions/0x560c1b26e301b588ac9586169967b50f53ec42e0b8f50efda5a4929fcb87e4e7) |

Gas: 0.0004 ZTH for demo 1, 0.0002 ZTH for demo 2. Records: `demo/broadcast/Demo1Borrow.s.sol/` and `demo/broadcast/Demo2Liquidate.s.sol/`.

### First liquidation on testnet

The first liquidation (before the demos were split, script then called `Liquidate.s.sol`) liquidated the position opened by the setup script: price dropped to 1,100 zUSD/zETH (10 zETH / 10,000 zUSD went from 50% to 90.9% LTV), liquidator `0x87f36CfCA238B1c3a1AD15889ec0B971F9A0F599`. Result on testnet (12 Nov 2026):

| | |
|---|---|
| Debt repaid by liquidator | 10,000.01 zUSD |
| Collateral seized | 9.4895 zETH (worth 10,438.43 zUSD at 1,100) |
| Liquidation incentive | 4.38% = `1 / (1 - 0.3 × (1 - 0.86))`, Morpho's formula |
| Borrower after | 0 debt, 0.5105 zETH collateral left |
| Liquidate tx | [`0x5ca1998b…3099b55`](https://explorer.testnet.zenith.network/transactions/0x5ca1998b237a09e02e52446526e683713c019ea7de8536a11b31762573099b55) |
| Price restore tx | [`0x03f493ea…4aa054b602`](https://explorer.testnet.zenith.network/transactions/0x03f493ea77f57b5dd7dd57692f5fbef9a4bfca0db7c545c7ac62748aa054b602) |

A first attempt (`demo/broadcast/Liquidate.s.sol/936485/run-1794481584218.json`) ran out of liquidator gas because of the high suggested tip above; the re-run (`run-1794481780457.json`) completed it.

## License

- `morpho-blue/` and `vault-v2/` are Morpho's code under their own licenses (GPL-2.0-or-later for `Morpho.sol`, `VaultV2.sol` and `VaultV2Factory.sol`; MIT for the rest). See the LICENSE files in each submodule.
- Everything else in this repository (scripts, `demo/`) is MIT, see [`LICENSE`](./LICENSE).
