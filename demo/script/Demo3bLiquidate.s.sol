// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {DemoBase} from "./DemoBase.sol";

/// Demo 3b — the borrower ignores the margin call (demo 2) and gets liquidated.
/// Also works straight after demo 1.
/// 1. Deployer: gives the liquidator ZTH for gas and enough zUSD to repay, then drops the oracle
///    price so the borrower's position goes to 95% LTV, above the 86% LLTV.
/// 2. Liquidator: repays the whole debt and seizes zETH collateral at a discount.
/// 3. Deployer: restores the oracle price.
/// Env: LIQUIDATOR. Optional: BORROWER (default deployer), CRASH_PRICE_USD (default: the price giving 95% LTV),
///      RESTORE_PRICE_USD (default 2000, fixed so a re-run after a partial failure still restores it).
contract Demo3bLiquidate is DemoBase {
    function run() external {
        _load();
        address liquidator = vm.envAddress("LIQUIDATOR");
        uint256 restorePrice = vm.envOr("RESTORE_PRICE_USD", uint256(2000)) * PRICE_SCALE;

        require(_debt() > 0, "borrower has no debt: run demo 1 (borrow) first");
        // Default crash price puts the position at 95% LTV, clearly above the 86% LLTV,
        // whatever collateral the borrower holds: price = debt / (collateral * 0.95).
        uint256 crashPrice = vm.envOr("CRASH_PRICE_USD", uint256(0)) * PRICE_SCALE;
        if (crashPrice == 0) crashPrice = _priceForLtv(9500);
        _report("BEFORE");

        // 1. Deployer: fund the liquidator, crash the price.
        vm.startBroadcast(deployer);
        _fundGas(liquidator);
        uint256 need = _debt() * 101 / 100; // +1% for interest accrued until the liquidation lands
        if (zUSD.balanceOf(liquidator) < need) zUSD.mint(liquidator, need - zUSD.balanceOf(liquidator));
        oracle.setPrice(crashPrice);
        vm.stopBroadcast();
        _report("AFTER PRICE DROP");

        // 2. Liquidator: repay everything, seize collateral.
        uint256 usdBefore = zUSD.balanceOf(liquidator);
        uint256 ethBefore = zETH.balanceOf(liquidator);
        uint256 shares = morpho.position(id, borrower).borrowShares;
        vm.startBroadcast(liquidator);
        if (zUSD.allowance(liquidator, address(morpho)) < need) zUSD.approve(address(morpho), type(uint256).max);
        (uint256 seized, uint256 repaid) = morpho.liquidate(mp, borrower, 0, shares, "");
        vm.stopBroadcast();
        console.log("--- LIQUIDATION");
        console.log("  crash price:                ", _price(crashPrice));
        console.log("  liquidator repaid:          ", _usd(repaid));
        console.log("  liquidator seized:          ", _eth(seized));
        console.log("  seized value at crash price:", _usd(seized * crashPrice / 1e36));
        console.log("  liquidator zUSD spent:      ", _usd(usdBefore - zUSD.balanceOf(liquidator)));
        console.log("  liquidator zETH received:   ", _eth(zETH.balanceOf(liquidator) - ethBefore));

        // 3. Deployer: restore the price.
        vm.startBroadcast(deployer);
        oracle.setPrice(restorePrice);
        vm.stopBroadcast();

        _report("AFTER LIQUIDATION (price restored)");
    }
}
