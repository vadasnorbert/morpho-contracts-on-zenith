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

    function _collateral() internal view returns (uint256) {
        return morpho.position(id, borrower).collateral;
    }

    /// Loan-to-value in basis points at `price` (oracle units).
    function _ltvBps(uint256 price) internal view returns (uint256) {
        uint256 collValue = _collateral() * price / 1e36;
        return collValue == 0 ? 0 : _debt() * 10_000 / collValue;
    }

    /// Oracle price (oracle units) at which the borrower's position sits at `bps` loan-to-value.
    function _priceForLtv(uint256 bps) internal view returns (uint256) {
        return _debt() * 1e36 * 10_000 / (_collateral() * bps);
    }

    /// Formats `v` (with `dec` decimals) as a number with 2 decimals, e.g. 1001.52.
    function _fmt(uint256 v, uint8 dec) internal pure returns (string memory) {
        uint256 cents = v * 100 / 10 ** dec;
        uint256 frac = cents % 100;
        return string.concat(vm.toString(cents / 100), frac < 10 ? ".0" : ".", vm.toString(frac));
    }

    function _usd(uint256 v) internal pure returns (string memory) {
        return string.concat(_fmt(v, 6), " zUSD");
    }

    function _eth(uint256 v) internal pure returns (string memory) {
        return string.concat(_fmt(v, 18), " zETH");
    }

    function _price(uint256 p) internal pure returns (string memory) {
        return string.concat(_fmt(p, 24), " zUSD per zETH");
    }

    function _pct(uint256 bps) internal pure returns (string memory) {
        return string.concat(_fmt(bps, 2), "%");
    }

    function _report(string memory label) internal view {
        uint256 price = oracle.price();
        Market memory m = morpho.market(id);
        console.log("---", label);
        console.log("  price:              ", _price(price));
        console.log("  borrower collateral:", _eth(_collateral()));
        console.log("  borrower debt:      ", _usd(_debt()));
        console.log("  loan-to-value:      ", string.concat(_pct(_ltvBps(price)), " (liquidation above 86.00%)"));
        console.log("  market supplied:    ", _usd(m.totalSupplyAssets));
        console.log("  market borrowed:    ", _usd(m.totalBorrowAssets));
        console.log("  vault total assets: ", _usd(vault.totalAssets()));
    }
}
