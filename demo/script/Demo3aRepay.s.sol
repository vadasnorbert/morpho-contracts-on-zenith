// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {DemoBase} from "./DemoBase.sol";

/// Demo 3a — the borrower answers the margin call (demo 2) by closing the loan.
/// 1. Borrower: repays the whole debt including interest, then withdraws all zETH collateral.
///    (A separate borrower gets the zUSD it is short of from the deployer.)
/// 2. Deployer: restores the oracle price, so demo 1 can run again.
/// Optional env: BORROWER (default deployer), RESTORE_PRICE_USD (default 2000).
contract Demo3aRepay is DemoBase {
    function run() external {
        _load();
        uint256 restorePrice = vm.envOr("RESTORE_PRICE_USD", uint256(2000)) * PRICE_SCALE;
        require(_debt() > 0, "borrower has no debt: run demo 1 (borrow) and demo 2 (margin call) first");

        _report("BEFORE");

        // Top up a separate borrower's zUSD (and gas) so it can repay principal + interest.
        uint256 need = _debt() * 101 / 100; // +1% for interest accrued until the repayment lands
        vm.startBroadcast(deployer);
        if (borrower != deployer) {
            _fundGas(borrower);
            if (zUSD.balanceOf(borrower) < need) zUSD.mint(borrower, need - zUSD.balanceOf(borrower));
        }
        vm.stopBroadcast();

        uint256 usdBefore = zUSD.balanceOf(borrower);
        uint256 shares = morpho.position(id, borrower).borrowShares;
        uint256 coll = _collateral();
        vm.startBroadcast(borrower);
        if (zUSD.allowance(borrower, address(morpho)) < need) zUSD.approve(address(morpho), type(uint256).max);
        (uint256 repaid,) = morpho.repay(mp, 0, shares, borrower, ""); // by shares: clears the debt exactly
        morpho.withdrawCollateral(mp, coll, borrower, borrower);
        vm.stopBroadcast();

        console.log("--- REPAYMENT");
        console.log("  repaid (principal + interest):", _usd(repaid));
        console.log("  borrower zUSD spent:          ", _usd(usdBefore - zUSD.balanceOf(borrower)));
        console.log("  collateral withdrawn:         ", _eth(coll));

        vm.startBroadcast(deployer);
        oracle.setPrice(restorePrice);
        vm.stopBroadcast();

        _report("AFTER REPAYMENT (price restored)");
    }
}
