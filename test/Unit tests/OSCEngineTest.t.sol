//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {OrenjiStableCoin} from "../../src/OrenjiStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract OSCTest is Test {
    DeployOSC deployer;
    OrenjiStableCoin osc;
    OSCEngine osce;
    HelperConfig config;
    address weth;
    address wethUsdPriceFeed;

    address public USER = makeAddr("user");
    uint256 constant ETH_AMOUNT_COLLATERAL = 4 ether;
    uint256 constant STARTING_ETH_AMOUNT = 20 ether;

    function setUp() public {
        deployer = new DeployOSC();
        (osc, osce, config) = deployer.run();
        (weth,, wethUsdPriceFeed,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ETH_AMOUNT);
    }

    ///////////////////////////////////
    //// Constructor Tests ///////////
    /////////////////////////////////

    //////////////////////
    //// Price Tests ////
    ////////////////////

    function testGetUsdValueOfCollateral() public {
        uint256 expectedUsdValue = 8000e18;
        uint256 actualUsdValue = osce.getUsdValueOfCollateral(weth, ETH_AMOUNT_COLLATERAL);
        console.log(expectedUsdValue, actualUsdValue);

        assert(actualUsdValue == expectedUsdValue);
    }

    ///////////////////////////////////
    //// Deposit Collateral Tests ////
    /////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(osce), ETH_AMOUNT_COLLATERAL);

        vm.expectRevert(OSCEngine.OSCEngine__MustBeMoreThanZero.selector);
        osce.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
