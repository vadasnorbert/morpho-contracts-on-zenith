// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {DemoBase} from "./DemoBase.sol";

/// Demo 2 — margin call on the position opened by demo 1 (Demo1Borrow).
/// The deployer (oracle owner) lowers the zETH price until the borrower's loan sits at 80% LTV:
/// still under the 86% liquidation threshold, but close. Morpho has no on-chain margin call; like in
/// traditional finance it is an alert, so this demo prints what a lender or a monitoring service would
/// send the borrower: current LTV, the liquidation price, and how much to repay or add as collateral.
/// The price stays down: continue with demo 3a (repay) or demo 3b (liquidate).
/// Optional env: BORROWER (default deployer), MARGIN_LTV_BPS (default 8000), SAFE_LTV_BPS (default 5000).
contract Demo2MarginCall is DemoBase {
    function run() external {
        _load();
        uint256 marginBps = vm.envOr("MARGIN_LTV_BPS", uint256(8000));
        uint256 safeBps = vm.envOr("SAFE_LTV_BPS", uint256(5000));
        require(marginBps < 8600, "MARGIN_LTV_BPS must stay below the 86% LLTV (8600)");
        require(_debt() > 0, "borrower has no debt: run demo 1 (borrow) first");
        require(_ltvBps(oracle.price()) < marginBps, "position is already at or above the margin-call level");

        _report("BEFORE");

        uint256 newPrice = _priceForLtv(marginBps);
        vm.startBroadcast(deployer);
        oracle.setPrice(newPrice);
        vm.stopBroadcast();

        _report("AFTER PRICE DROP");

        uint256 debt = _debt();
        uint256 coll = _collateral();
        uint256 liqPrice = _priceForLtv(8600);
        // To get back to SAFE_LTV: repay down to coll*price*safe, or add collateral up to debt/(price*safe).
        uint256 maxSafeDebt = coll * newPrice / 1e36 * safeBps / 10_000;
        uint256 repayNeeded = debt > maxSafeDebt ? debt - maxSafeDebt : 0;
        uint256 collNeeded = debt * 1e36 * 10_000 / (newPrice * safeBps);
        uint256 addNeeded = collNeeded > coll ? collNeeded - coll : 0;

        console.log("=== MARGIN CALL ===");
        console.log("  borrower:          ", borrower);
        console.log("  loan-to-value:     ", string.concat(_pct(_ltvBps(newPrice)), " (margin call at ", _pct(marginBps), ")"));
        console.log("  liquidation price: ", string.concat(_price(liqPrice), " (", _pct((newPrice - liqPrice) * 10_000 / newPrice), " below the current price)"));
        console.log(string.concat("  to get back to ", _pct(safeBps), " LTV, either:"));
        console.log("    repay:           ", _usd(repayNeeded));
        console.log("    or add:          ", _eth(addNeeded));
        console.log("  next: demo 3a (./demo.sh repay) or demo 3b (./demo.sh liquidate)");
    }
}
