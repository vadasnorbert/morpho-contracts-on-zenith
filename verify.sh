#!/usr/bin/env bash
# Verifies all deployed contracts on the Zenith testnet explorer.
set -uo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; . ./deployments.env; set +a
V=(--chain-id 936485 --verifier etherscan --verifier-url https://explorer.testnet.zenith.network/api --etherscan-api-key dummy --watch)
enc() { cast abi-encode "$@"; }
verify() { # <dir> <address> <path:Contract> [encoded constructor args]
  local dir=$1 addr=$2 target=$3 args=${4:-}
  echo "== $target @ $addr"
  (cd "$dir" && forge verify-contract "$addr" "$target" "${V[@]}" ${args:+--constructor-args "$args"} 2>&1 \
    | grep -E "Contract successfully verified|already verified|Details|Error" | tail -2)
}
verify morpho-blue "$MORPHO" src/Morpho.sol:Morpho "$(enc 'c(address)' "$DEPLOYER_ADDRESS")"
verify morpho-blue "$ADAPTIVE_CURVE_IRM" src/periphery/adaptive-curve-irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm "$(enc 'c(address)' "$MORPHO")"
verify morpho-blue "$PRE_LIQUIDATION_FACTORY" src/periphery/pre-liquidation/PreLiquidationFactory.sol:PreLiquidationFactory "$(enc 'c(address)' "$MORPHO")"
verify vault-v2 "$VAULT_V2_FACTORY" src/VaultV2Factory.sol:VaultV2Factory
verify vault-v2 "$MORPHO_MARKET_V1_ADAPTER_V2_FACTORY" src/adapters/MorphoMarketV1AdapterV2Factory.sol:MorphoMarketV1AdapterV2Factory "$(enc 'c(address,address)' "$MORPHO" "$ADAPTIVE_CURVE_IRM")"
verify vault-v2 "$VAULT_ZUSD" src/VaultV2.sol:VaultV2 "$(enc 'c(address,address)' "$DEPLOYER_ADDRESS" "$ZUSD")"
verify vault-v2 "$VAULT_ZUSD_ADAPTER" src/adapters/MorphoMarketV1AdapterV2.sol:MorphoMarketV1AdapterV2 "$(enc 'c(address,address,address)' "$VAULT_ZUSD" "$MORPHO" "$ADAPTIVE_CURVE_IRM")"
verify demo "$ZUSD" src/TestToken.sol:TestToken "$(enc 'c(string,string,uint8)' 'Zenith Test Dollar' zUSD 6)"
verify demo "$ZETH" src/TestToken.sol:TestToken "$(enc 'c(string,string,uint8)' 'Zenith Test Ether' zETH 18)"
verify demo "$FIXED_PRICE_ORACLE" src/FixedPriceOracle.sol:FixedPriceOracle "$(enc 'c(uint256)' 2000000000000000000000000000)"
