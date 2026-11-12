// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {DemoBase} from "./DemoBase.sol";

/// Demo 1 — lend and borrow on the zETH/zUSD 86% market.
/// 1. Deployer: makes sure the oracle price is 2,000 zUSD/zETH, mints zUSD to itself and
///    zETH (+ ZTH for gas) to the borrower.
/// 2. Lender (deployer): deposits zUSD into the "ZLP zUSD Vault", which supplies it to the market.
/// 3. Borrower: posts zETH collateral and borrows zUSD at 50% LTV.
/// Next: demo 2 (Demo2MarginCall), then demo 3a (Demo3aRepay) or 3b (Demo3bLiquidate).
/// Optional env: BORROWER (default deployer), LEND_ZUSD (default 20000), COLLATERAL_ZETH (default 10),
///               BORROW_ZUSD (default 10000), PRICE_USD (default 2000).
contract Demo1Borrow is DemoBase {
    function run() external {
        _load();
        uint256 lend = vm.envOr("LEND_ZUSD", uint256(20_000)) * 1e6;
        uint256 coll = vm.envOr("COLLATERAL_ZETH", uint256(10)) * 1e18;
        uint256 borrow = vm.envOr("BORROW_ZUSD", uint256(10_000)) * 1e6;
        uint256 price = vm.envOr("PRICE_USD", uint256(2000)) * PRICE_SCALE;

        _report("BEFORE");

        // 1 + 2. Deployer: price, tokens, lend into the vault.
        vm.startBroadcast(deployer);
        if (oracle.price() != price) oracle.setPrice(price);
        if (zUSD.balanceOf(deployer) < lend) zUSD.mint(deployer, lend);
        if (zETH.balanceOf(borrower) < coll) zETH.mint(borrower, coll - zETH.balanceOf(borrower));
        _fundGas(borrower);
        if (zUSD.allowance(deployer, address(vault)) < lend) zUSD.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(lend, deployer);
        vm.stopBroadcast();
        console.log("--- LEND");
        console.log("  deposited into ZLP zUSD Vault:", _usd(lend));
        console.log("  vault shares received:        ", string.concat(_fmt(shares, 18), " zlpUSD"));

        // 3. Borrower: collateral + borrow.
        vm.startBroadcast(borrower);
        if (zETH.allowance(borrower, address(morpho)) < coll) zETH.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(mp, coll, borrower, "");
        morpho.borrow(mp, borrow, 0, borrower, borrower);
        vm.stopBroadcast();
        console.log("--- BORROW");
        console.log("  collateral posted:", _eth(coll));
        console.log("  borrowed:         ", _usd(borrow));

        _report("AFTER");
        console.log("  next: demo 2 (./demo.sh margin-call)");
    }
}
