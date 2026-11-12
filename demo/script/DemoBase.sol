// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {FixedPriceOracle} from "../src/FixedPriceOracle.sol";
import {TestToken} from "../src/TestToken.sol";

/// Shared setup for the demos: loads the deployment from env and prints positions.
/// Env (from .env + deployments.env): MORPHO, ADAPTIVE_CURVE_IRM, ZUSD, ZETH, FIXED_PRICE_ORACLE,
/// VAULT_ZUSD, DEPLOYER_ADDRESS. Optional: BORROWER (default deployer).
abstract contract DemoBase is Script {
    using MarketParamsLib for MarketParams;

    uint256 constant LLTV = 0.86e18;
    uint256 constant PRICE_SCALE = 1e24; // 1 zUSD per zETH in oracle units (1e36 * 1e6 / 1e18)

    IMorpho morpho;
    TestToken zUSD;
    TestToken zETH;
    FixedPriceOracle oracle;
    IVaultV2 vault;
    address deployer;
    address borrower;
    MarketParams mp;
    Id id;

    function _load() internal {
        morpho = IMorpho(vm.envAddress("MORPHO"));
        zUSD = TestToken(vm.envAddress("ZUSD"));
        zETH = TestToken(vm.envAddress("ZETH"));
        oracle = FixedPriceOracle(vm.envAddress("FIXED_PRICE_ORACLE"));
        vault = IVaultV2(vm.envAddress("VAULT_ZUSD"));
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        borrower = vm.envOr("BORROWER", deployer);
        mp = MarketParams({
            loanToken: address(zUSD),
            collateralToken: address(zETH),
            oracle: address(oracle),
            irm: vm.envAddress("ADAPTIVE_CURVE_IRM"),
            lltv: LLTV
        });
        id = mp.id();
    }

    /// Gives a non-deployer wallet ZTH for gas (must be called inside a deployer broadcast).
    function _fundGas(address who) internal {
        if (who != deployer && who.balance < 0.05 ether) payable(who).transfer(0.1 ether);
    }

    function _debt() internal view returns (uint256) {
        Market memory m = morpho.market(id);
        if (m.totalBorrowShares == 0) return 0;
        return uint256(morpho.position(id, borrower).borrowShares) * m.totalBorrowAssets / m.totalBorrowShares;
    }

    function _report(string memory label) internal view {
        uint256 price = oracle.price();
        Position memory p = morpho.position(id, borrower);
        Market memory m = morpho.market(id);
        uint256 debt = _debt();
        uint256 collValue = uint256(p.collateral) * price / 1e36;
        console.log("---", label);
        console.log("price zUSD per zETH:", price / PRICE_SCALE);
        console.log("borrower collateral zETH (18 dp):", p.collateral);
        console.log("borrower debt zUSD (6 dp):", debt);
        console.log("borrower LTV bps (liquidatable above 8600):", collValue == 0 ? 0 : debt * 10_000 / collValue);
        console.log("market supplied / borrowed zUSD (6 dp):", m.totalSupplyAssets, m.totalBorrowAssets);
        console.log("vault total assets zUSD (6 dp):", vault.totalAssets());
    }
}
