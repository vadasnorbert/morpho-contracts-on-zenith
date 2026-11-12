# Morpho on Zenith EVM testnet

Deployment of the open-source [Morpho](https://github.com/morpho-org) lending stack (Morpho core + Vault V2) on **Zenith EVM testnet**, plus a demo zUSD/zETH market and vault.

User-facing, this deployment is branded **ZLP — Zenith Lending Protocol** (e.g. the vault is named "ZLP zUSD Vault", symbol `zlpUSD`). ZLP is not affiliated with or endorsed by Morpho; it runs Morpho's unmodified open-source contracts.

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
| `demo/` | Foundry project: `TestToken`, `FixedPriceOracle`, and `script/Setup.s.sol` (tokens, oracle, market, vault, demo deposit + borrow) |
| `demo/broadcast/` | Transaction records of the demo setup run |
| `verify.sh` | Publishes the source of all deployed contracts on the explorer |
| `deployments.env` | Deployed addresses |
| `deploy.log`, `demo-setup.log` | Output of the deployment runs |

## Usage

Requires [Foundry](https://getfoundry.sh/).

```sh
git clone --recurse-submodules https://github.com/vadasnorbert/morpho-zenith
cd morpho-zenith
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

Create the demo tokens, oracle, market and vault:

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
  --rpc-url "$ZENITH_RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

## License

- `morpho-blue/` and `vault-v2/` are Morpho's code under their own licenses (GPL-2.0-or-later for `Morpho.sol`, `VaultV2.sol` and `VaultV2Factory.sol`; MIT for the rest). See the LICENSE files in each submodule.
- Everything else in this repository (scripts, `demo/`) is MIT, see [`LICENSE`](./LICENSE).
