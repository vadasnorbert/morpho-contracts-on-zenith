#!/usr/bin/env bash
# Deploys the Morpho stack to Zenith EVM testnet and writes addresses to deployments.env.
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
RPC="${RPC_OVERRIDE:-$ZENITH_RPC_URL}"; OUT_FILE="${OUT_FILE:-deployments.env}"
OUT="$OUT_FILE"
: > "$OUT"

# Signer: encrypted Foundry keystore (~/.foundry/keystores/$DEPLOYER_ACCOUNT). Prompts for the password,
# unless KEYSTORE_PASSWORD_FILE points to a file holding it.
SIGNER=(--account "${DEPLOYER_ACCOUNT:-zenith-deployer}")
[ -n "${KEYSTORE_PASSWORD_FILE:-}" ] && SIGNER+=(--password-file "$KEYSTORE_PASSWORD_FILE")

create() { # <repo> <path:Contract> [constructor args...]
  local repo=$1 target=$2; shift 2
  local args=(); [ $# -gt 0 ] && args=(--constructor-args "$@")
  local addr
  addr=$(cd "$repo" && forge create "$target" --rpc-url "$RPC" "${SIGNER[@]}" --broadcast ${args[@]+"${args[@]}"} 2>&1 \
    | tee /dev/stderr | awk '/Deployed to:/{print $3}')
  [ -n "$addr" ] || { echo "deploy of $target failed" >&2; exit 1; }
  echo "$addr"
}
send() { cast send "$@" --rpc-url "$RPC" "${SIGNER[@]}" >/dev/null; }

MORPHO=$(create morpho-blue src/Morpho.sol:Morpho "$DEPLOYER_ADDRESS")
echo "MORPHO=$MORPHO" >> "$OUT"
IRM=$(create morpho-blue src/periphery/adaptive-curve-irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm "$MORPHO")
echo "ADAPTIVE_CURVE_IRM=$IRM" >> "$OUT"
PRELIQ=$(create morpho-blue src/periphery/pre-liquidation/PreLiquidationFactory.sol:PreLiquidationFactory "$MORPHO")
echo "PRE_LIQUIDATION_FACTORY=$PRELIQ" >> "$OUT"

# Governance: enable the IRM and the standard Morpho LLTVs (77%, 86%, 91.5%, 94.5%).
send "$MORPHO" "enableIrm(address)" "$IRM"
for l in 770000000000000000 860000000000000000 915000000000000000 945000000000000000; do
  send "$MORPHO" "enableLltv(uint256)" "$l"
done

VFACTORY=$(create vault-v2 src/VaultV2Factory.sol:VaultV2Factory)
echo "VAULT_V2_FACTORY=$VFACTORY" >> "$OUT"
AFACTORY=$(create vault-v2 src/adapters/MorphoMarketV1AdapterV2Factory.sol:MorphoMarketV1AdapterV2Factory "$MORPHO" "$IRM")
echo "MORPHO_MARKET_V1_ADAPTER_V2_FACTORY=$AFACTORY" >> "$OUT"

echo "--- done"; cat "$OUT"
