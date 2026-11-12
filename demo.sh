#!/usr/bin/env bash
# Runs the demos on Zenith EVM testnet, in order 1 -> 2 -> 3a or 3b:
#   ./demo.sh borrow        demo 1:  lend into the ZLP zUSD Vault, borrow zUSD against zETH
#   ./demo.sh margin-call   demo 2:  price drops, the loan reaches 80% LTV, margin call printed
#   ./demo.sh repay         demo 3a: borrower repays the loan and withdraws collateral
#   ./demo.sh liquidate     demo 3b: price drops further, liquidator repays and seizes collateral
# Extra arguments are passed to forge (e.g. --rpc-url http://127.0.0.1:8545 to try on a local fork).
# Signs with the encrypted keystores named in .env (DEPLOYER_ACCOUNT, LIQUIDATOR_ACCOUNT, optional BORROWER_ACCOUNT).
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; . ./deployments.env; set +a

case "${1:-}" in
  borrow)      script=script/Demo1Borrow.s.sol;      accounts=("$DEPLOYER_ACCOUNT" ${BORROWER_ACCOUNT:+"$BORROWER_ACCOUNT"}) ;;
  margin-call) script=script/Demo2MarginCall.s.sol;  accounts=("$DEPLOYER_ACCOUNT") ;;
  repay)       script=script/Demo3aRepay.s.sol;      accounts=("$DEPLOYER_ACCOUNT" ${BORROWER_ACCOUNT:+"$BORROWER_ACCOUNT"}) ;;
  liquidate)   script=script/Demo3bLiquidate.s.sol;  accounts=("$DEPLOYER_ACCOUNT" "$LIQUIDATOR_ACCOUNT") ;;
  *) echo "usage: $0 borrow|margin-call|repay|liquidate [forge args...]" >&2; exit 1 ;;
esac
shift

account_args=()
for a in "${accounts[@]}"; do account_args+=(--account "$a"); done

# The testnet RPC suggests a ~600 gwei tip while the base fee is 7 wei; cap it at 1 gwei.
# Gas estimates come from a simulation where no time has passed; interest accrual costs more on chain, so double them.
cd demo
exec forge script "$script" --rpc-url "$ZENITH_RPC_URL" --broadcast --slow \
  --with-gas-price 2gwei --priority-gas-price 1gwei --gas-estimate-multiplier 200 \
  "${account_args[@]}" --sender "$DEPLOYER_ADDRESS" "$@"
