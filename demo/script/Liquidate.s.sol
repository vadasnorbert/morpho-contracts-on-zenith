// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {FixedPriceOracle} from "../src/FixedPriceOracle.sol";
import {TestToken} from "../src/TestToken.sol";

/// Liquidation demo on the zETH/zUSD 86% market:
/// 1. drop the oracle price so the demo borrower's position goes above the 86% LLTV,
/// 2. liquidate the whole debt (liquidator repays zUSD, seizes zETH at a discount),
/// 3. restore the oracle price.
/// Env: MORPHO, ZUSD, ZETH, FIXED_PRICE_ORACLE, ADAPTIVE_CURVE_IRM, DEPLOYER_ADDRESS.
/// Optional: LIQUIDATOR (default deployer; a separate one gets 0.1 ZTH + zUSD from the deployer),
///           BORROWER (default deployer), CRASH_PRICE_USD (default 1100), RESTORE_PRICE_USD (default 2000).
contract Liquidate is Script {
    using MarketParamsLib for MarketParams;

    uint256 constant LLTV = 0.86e18;

    IMorpho morpho;
    IERC20 zUSD;
    IERC20 zETH;
    FixedPriceOracle oracle;
    address liquidator;
    address borrower;
    MarketParams mp;
    Id id;

    function run() external {
        morpho = IMorpho(vm.envAddress("MORPHO"));
        zUSD = IERC20(vm.envAddress("ZUSD"));
        zETH = IERC20(vm.envAddress("ZETH"));
        oracle = FixedPriceOracle(vm.envAddress("FIXED_PRICE_ORACLE"));
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        liquidator = vm.envOr("LIQUIDATOR", deployer);
        borrower = vm.envOr("BORROWER", deployer);
        uint256 crashPrice = vm.envOr("CRASH_PRICE_USD", uint256(1100)) * 1e24;
        mp = MarketParams({
            loanToken: address(zUSD),
            collateralToken: address(zETH),
            oracle: address(oracle),
            irm: vm.envAddress("ADAPTIVE_CURVE_IRM"),
            lltv: LLTV
        });
        id = mp.id();
        // Fixed restore price (not read from the oracle) so a re-run after a partial failure still restores it.
        uint256 originalPrice = vm.envOr("RESTORE_PRICE_USD", uint256(2000)) * 1e24;

        _report("BEFORE", oracle.price());

        // Deployer (oracle owner, token minter): fund a separate liquidator, then crash the price.
        vm.startBroadcast(deployer);
        if (liquidator != deployer) {
            if (liquidator.balance < 0.05 ether) payable(liquidator).transfer(0.1 ether); // ZTH for gas
            uint256 need = _debt() * 101 / 100;
            uint256 has = zUSD.balanceOf(liquidator);
            if (has < need) TestToken(address(zUSD)).mint(liquidator, need - has);
        }
        oracle.setPrice(crashPrice);
        morpho.accrueInterest(mp);
        vm.stopBroadcast();
        _report("AFTER PRICE DROP", crashPrice);

        // Liquidator: repay the debt, seize the collateral.
        vm.startBroadcast(liquidator);
        _liquidate(crashPrice);
        vm.stopBroadcast();

        // Deployer: restore the price.
        vm.startBroadcast(deployer);
        oracle.setPrice(originalPrice);
        vm.stopBroadcast();

        _report("AFTER LIQUIDATION (price restored)", originalPrice);
    }

    function _liquidate(uint256 crashPrice) internal {
        uint256 usdBefore = zUSD.balanceOf(liquidator);
        uint256 ethBefore = zETH.balanceOf(liquidator);
        zUSD.approve(address(morpho), type(uint256).max);
        (uint256 seized, uint256 repaid) =
            morpho.liquidate(mp, borrower, 0, morpho.position(id, borrower).borrowShares, "");

        console.log("--- LIQUIDATION");
        console.log("repaid zUSD (6 dp):", repaid);
        console.log("seized zETH (18 dp):", seized);
        console.log("seized value at crash price, zUSD (6 dp):", seized * crashPrice / 1e36);
        console.log("liquidator zUSD spent:", usdBefore - zUSD.balanceOf(liquidator));
        console.log("liquidator zETH received:", zETH.balanceOf(liquidator) - ethBefore);
    }

    function _debt() internal view returns (uint256) {
        Market memory m = morpho.market(id);
        if (m.totalBorrowShares == 0) return 0;
        return uint256(morpho.position(id, borrower).borrowShares) * m.totalBorrowAssets / m.totalBorrowShares;
    }

    function _report(string memory label, uint256 price) internal view {
        Position memory p = morpho.position(id, borrower);
        uint256 debt = _debt();
        uint256 collValue = uint256(p.collateral) * price / 1e36;
        console.log("---", label);
        console.log("price zUSD per zETH:", price / 1e24);
        console.log("collateral zETH (18 dp):", p.collateral);
        console.log("debt zUSD (6 dp):", debt);
        console.log("LTV bps (liquidatable above 8600):", collValue == 0 ? 0 : debt * 10_000 / collValue);
    }
}
