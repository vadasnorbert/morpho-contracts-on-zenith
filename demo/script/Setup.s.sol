// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IMorpho, MarketParams, Id} from "morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/interfaces/IVaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {TestToken} from "../src/TestToken.sol";
import {FixedPriceOracle} from "../src/FixedPriceOracle.sol";

/// Creates zUSD/zETH, a fixed 2,000 zUSD/zETH oracle, an 86% LLTV market,
/// and a vault ("ZLP zUSD Vault") lending into it, then runs a demo deposit + borrow.
contract Setup is Script {
    using MarketParamsLib for MarketParams;

    uint256 constant WAD = 1e18;
    uint256 constant PRICE = 2000 * 1e24; // 2000e6 loan units per 1e18 collateral units, scaled by 1e36
    uint256 constant LLTV = 0.86e18;
    uint256 constant CAP = 10_000_000e6; // 10M zUSD per cap id

    function run() external {
        address me = vm.envAddress("DEPLOYER_ADDRESS");
        IMorpho morpho = IMorpho(vm.envAddress("MORPHO"));
        address irm = vm.envAddress("ADAPTIVE_CURVE_IRM");

        vm.startBroadcast(me); // signer comes from --account (encrypted keystore)

        // 1. Tokens
        TestToken zUSD = new TestToken("Zenith Test Dollar", "zUSD", 6);
        TestToken zETH = new TestToken("Zenith Test Ether", "zETH", 18);
        zUSD.mint(me, 10_000_000e6);
        zETH.mint(me, 10_000e18);

        // 2. Oracle + market
        FixedPriceOracle oracle = new FixedPriceOracle(PRICE);
        MarketParams memory mp = MarketParams({
            loanToken: address(zUSD), collateralToken: address(zETH), oracle: address(oracle), irm: irm, lltv: LLTV
        });
        morpho.createMarket(mp);

        // 3. Vault (owner = curator = allocator = deployer)
        IVaultV2 vault = IVaultV2(IVaultV2Factory(vm.envAddress("VAULT_V2_FACTORY")).createVaultV2(me, address(zUSD), bytes32(0)));
        vault.setName("ZLP zUSD Vault");
        vault.setSymbol("zlpUSD");
        vault.setCurator(me);
        address adapter = IMorphoMarketV1AdapterV2Factory(vm.envAddress("MORPHO_MARKET_V1_ADAPTER_V2_FACTORY"))
            .createMorphoMarketV1AdapterV2(address(vault));

        // Curator actions are timelocked; timelocks start at 0, so submit + execute in one go.
        _curate(vault, abi.encodeCall(IVaultV2.setIsAllocator, (me, true)));
        _curate(vault, abi.encodeCall(IVaultV2.addAdapter, (adapter)));
        bytes[3] memory idData =
            [abi.encode("this", adapter), abi.encode("collateralToken", address(zETH)), abi.encode("this/marketParams", adapter, mp)];
        for (uint256 i; i < 3; i++) {
            _curate(vault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData[i], CAP)));
            _curate(vault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData[i], WAD)));
        }
        vault.setLiquidityAdapterAndData(adapter, abi.encode(mp)); // deposits flow straight into the market
        vault.setMaxRate(200e16 / uint256(365 days));

        // 4. Demo: lend 100k zUSD via the vault, borrow 10k zUSD against 10 zETH (50% LTV)
        zUSD.approve(address(vault), type(uint256).max);
        vault.deposit(100_000e6, me);
        zETH.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(mp, 10e18, me, "");
        morpho.borrow(mp, 10_000e6, 0, me, me);

        vm.stopBroadcast();

        console.log("ZUSD", address(zUSD));
        console.log("ZETH", address(zETH));
        console.log("ORACLE", address(oracle));
        console.log("VAULT", address(vault));
        console.log("ADAPTER", adapter);
        console.logBytes32(Id.unwrap(mp.id()));
    }

    function _curate(IVaultV2 vault, bytes memory data) internal {
        vault.submit(data);
        (bool ok, bytes memory ret) = address(vault).call(data);
        if (!ok) assembly { revert(add(ret, 32), mload(ret)) }
    }
}
