//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {OSCEngine} from "../src/OSCEngine.sol";
import {OrenjiStableCoin} from "../src/OrenjiStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployOSC is Script {
    OrenjiStableCoin orenjiStableCoin;
    OSCEngine oscEngine;

    address[] public collateralAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (OrenjiStableCoin, OSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address weth,
            address wbtc,
            address wethUsdPriceFeedAddress,
            address wbtcUsdPriceFeedAddress,
            uint256 deployerKey
        ) = config.activeNetworkConfig();
        collateralAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        orenjiStableCoin = new OrenjiStableCoin();
        oscEngine = new OSCEngine(collateralAddresses, priceFeedAddresses, address(orenjiStableCoin));

        orenjiStableCoin.transferOwnership(address(oscEngine));
        vm.stopBroadcast();

        return (orenjiStableCoin, oscEngine, config);
    }
}
