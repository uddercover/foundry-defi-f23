//SPDX-License-Identifier: MIT

/*
* Our Invariants:
* We want to always have more collateral than minted Osc
* We want view functions to never revert
*/
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {OrenjiStableCoin} from "../../src/OrenjiStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    Handler handler;
    DeployOSC deployer;
    OSCEngine osce;
    OrenjiStableCoin osc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployOSC();
        (osc, osce, config) = deployer.run();
        (weth, wbtc,,,) = config.activeNetworkConfig();
        handler = new Handler(osce, osc);
        targetContract(address(handler));
    }

    function invariant_testTotalMintedOscIsAlwaysLessThanTotalCollateralValue() public {
        //get the total value of collateral in the system
        //get the total value of osc in the system
        //compare them so the invariant holds

        uint256 totalWeth = ERC20Mock(weth).balanceOf(address(osce));
        uint256 totalWbtc = ERC20Mock(wbtc).balanceOf(address(osce));

        uint256 totalWethValue = osce.getUsdValueOfCollateral(weth, totalWeth);
        uint256 totalWbtcValue = osce.getUsdValueOfCollateral(wbtc, totalWbtc);

        uint256 totalCollateralValue = totalWethValue + totalWbtcValue;
        uint256 totalOscMinted = osce.getTotalSupplyOfOscMinted();

        console.log("Total Weth Value: ", totalWethValue);
        console.log("Total Wbtc Value: ", totalWbtcValue);
        console.log("Total Osc Minted: ", totalOscMinted);

        assert(totalCollateralValue >= totalOscMinted);
    }

    function invariant_testGettersNeverRevert() public view {
        osce.getCollateralTokenAddresses();
        osce.getTotalSupplyOfOscMinted();
    }
}
