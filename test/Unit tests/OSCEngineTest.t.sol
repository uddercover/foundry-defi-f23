//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {OrenjiStableCoin} from "../../src/OrenjiStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";

contract OSCTest is Test {
    DeployOSC deployer;
    OrenjiStableCoin osc;
    OSCEngine osce;
    HelperConfig config;
    address weth;
    address wethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public DAVE = makeAddr("dave");
    uint256 constant ETH_AMOUNT_COLLATERAL = 4 ether;
    uint256 constant STARTING_ETH_AMOUNT = 20 ether;
    uint256 constant DEFAULT_OSC_VALUE = 2000;
    int256 constant NEW_ETH_PRICE = 800e8;

    function setUp() public {
        deployer = new DeployOSC();
        (osc, osce, config) = deployer.run();
        (weth, btcUsdPriceFeed, wethUsdPriceFeed,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ETH_AMOUNT);
        ERC20Mock(weth).mint(DAVE, STARTING_ETH_AMOUNT);
    }

    ///////////////
    // modifiers //
    ///////////////

    modifier userDepositedWeth() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(osce), ETH_AMOUNT_COLLATERAL);
        osce.depositCollateral(address(weth), ETH_AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier userDepositedWethAndMintedOsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(osce), ETH_AMOUNT_COLLATERAL);
        osce.depositCollateralAndMintOsc(address(weth), ETH_AMOUNT_COLLATERAL, DEFAULT_OSC_VALUE);
        vm.stopPrank();
        _;
    }

    modifier daveDepositedWethAndMintedOsc() {
        vm.startPrank(DAVE);
        ERC20Mock(weth).approve(address(osce), STARTING_ETH_AMOUNT);

        osce.depositCollateralAndMintOsc(weth, STARTING_ETH_AMOUNT, DEFAULT_OSC_VALUE);
        vm.stopPrank();
        _;
    }

    modifier daveApprovesOsc() {
        vm.startPrank(DAVE);
        ERC20Mock(address(osc)).approve(address(osce), DEFAULT_OSC_VALUE);
        vm.stopPrank();
        _;
    }

    ///////////////////////////////////
    //// Constructor Tests ///////////
    /////////////////////////////////

    address[] priceFeedAddresses;
    address[] collateralAddresses;

    function testRevertIfCollateralAddressesAndPriceFeedAreNotTheSameLength() public {
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        collateralAddresses.push(weth);

        vm.expectRevert(OSCEngine.OSCEngine__CollateralAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        OSCEngine oscEngine = new OSCEngine(priceFeedAddresses, collateralAddresses, address(osc));
    }

    //////////////////////
    //// Price Tests ////
    ////////////////////

    function testGetUsdValueOfCollateral() public {
        uint256 expectedUsdValue = 8000e18;
        uint256 actualUsdValue = osce.getUsdValueOfCollateral(weth, ETH_AMOUNT_COLLATERAL);

        assert(actualUsdValue == expectedUsdValue);
    }

    function testGetCollateralAmountFromUsd() public {
        uint256 usdAmount = 1000e18;
        //$2000 per eth, $1000
        uint256 expectedCollateralAmount = 0.5 ether;
        uint256 actualCollateralAmount = osce.getCollateralAmountFromUsd(weth, usdAmount);

        assertEq(actualCollateralAmount, expectedCollateralAmount);
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

    function testRevertsIfCollateralIsNotAllowed() public {
        ERC20Mock random = new ERC20Mock();
        random.mint(USER, ETH_AMOUNT_COLLATERAL);
        ERC20Mock(random).approve(address(osce), ETH_AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(OSCEngine.OSCEngine__CollateralNotAllowed.selector);
        osce.depositCollateral(address(random), ETH_AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralValueIsTrackedAndCanGetAccountInformation() public userDepositedWeth {
        (uint256 totalOscMinted, uint256 collateralValueInUsd) = osce.getUserAccountInformation(USER);

        uint256 expectedTotalOscMinted = 0;
        uint256 expectedCollateralValueInUsd = osce.getUsdValueOfCollateral(address(weth), ETH_AMOUNT_COLLATERAL);

        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(totalOscMinted, expectedTotalOscMinted);
    }

    function testRevertsWhenUserDoesNotHaveEnoughFunds() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(osce), 50 ether);
        vm.expectRevert();

        osce.depositCollateral(address(weth), 50 ether);
        vm.stopPrank();
    }

    ////////////////////
    /// mintOsc Tests///
    ////////////////////

    function testRevertsIfHealthFactorIsBrokenWhenMintingOSC() public userDepositedWeth {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BreaksHealthFactor.selector, 8e17));
        osce.mintOsc(5000);
    }

    ///////////////////////////////////////////
    /// depositCollateral and mintOsc Tests///
    /////////////////////////////////////////
    function testUserCanDepositCollateralandMintOsc() public {
        uint256 expectedOscMinted = 1000;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(osce), 1 ether);
        osce.depositCollateralAndMintOsc(weth, 1 ether, 1000);
        (uint256 actualOscMinted,) = osce.getUserAccountInformation(USER);
        vm.stopPrank();

        assert(expectedOscMinted == actualOscMinted);
    }

    ////////////////////
    /// burnOsc Tests///
    ////////////////////
    function testUserCanBurnOsc() public userDepositedWethAndMintedOsc {
        uint256 expectedOscRemaining = 1200;
        vm.startPrank(USER);
        ERC20Mock(address(osc)).approve(address(osce), DEFAULT_OSC_VALUE);
        osce.burnOsc(800);
        (uint256 oscRemaining,) = osce.getUserAccountInformation(USER);
        vm.stopPrank();

        assertEq(oscRemaining, expectedOscRemaining);
    }

    /////////////////////////////
    /// redeemCollateral Tests///
    /////////////////////////////

    function testRevertsIfHealthFactorIsBrokenWhenRedeemingCollateral() public userDepositedWethAndMintedOsc {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BreaksHealthFactor.selector, 0));
        osce.redeemCollateral(weth, ETH_AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testUserAccountInformationGetsUpdatedAfterRedeemingCollateral() public userDepositedWethAndMintedOsc {
        uint256 expectedTotalCollateralDepositedInUsd = 6e21;
        vm.prank(USER);
        osce.redeemCollateral(weth, 1 ether);
        (, uint256 totalCollateralDepositedInUsd) = osce.getUserAccountInformation(USER);

        assertEq(expectedTotalCollateralDepositedInUsd, totalCollateralDepositedInUsd);
    }

    ///////////////////////////////////////
    /// redeemCollateralAndBurnOsc Tests///
    ///////////////////////////////////////

    function testUserCanRedeemCollateralAndBurnOsc() public userDepositedWethAndMintedOsc {
        uint256 expectedOscRemaining = 1200;
        uint256 expectedCollateralRemainingInUsd = 5e21;

        vm.startPrank(USER);
        ERC20Mock(address(osc)).approve(address(osce), DEFAULT_OSC_VALUE);
        osce.redeemCollateralandBurnOsc(weth, 15e17, 800);
        vm.stopPrank();

        (uint256 oscRemaining, uint256 collateralRemainingInUsd) = osce.getUserAccountInformation(USER);

        assertEq(expectedCollateralRemainingInUsd, collateralRemainingInUsd);
        assertEq(expectedOscRemaining, oscRemaining);
    }

    /////////////////////////////
    /// liquidate Tests /////////
    /////////////////////////////

    function testRevertsWhenDebtorDoesntBreakHealthFactor() public userDepositedWethAndMintedOsc {
        vm.expectRevert(OSCEngine.OSCEngine__HealthFactorIsStable.selector);
        osce.liquidate(USER, DEFAULT_OSC_VALUE, weth);
    }

    function testCollateralValuePaidToLiquidatorIs10PercentMoreThanDebtPaid()
        public
        userDepositedWethAndMintedOsc
        daveDepositedWethAndMintedOsc
        daveApprovesOsc
    {
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(NEW_ETH_PRICE);
        console.log("User health factor", osce.getUserHealthFactor(USER));

        vm.startPrank(DAVE);
        osce.liquidate(USER, 2000, weth);
        vm.stopPrank();

        uint256 expectedDaveWethBalance = 2.75 ether;
        uint256 actualDaveWethBalance = ERC20Mock(address(weth)).balanceOf(DAVE);

        assertEq(expectedDaveWethBalance, actualDaveWethBalance);
    }

    function testRevertsIfHealthFactorDoesNotImprove() public userDepositedWethAndMintedOsc {}

    function testRevertsIfLiquidatorHealthFactorIsBroken()
        public
        userDepositedWethAndMintedOsc
        daveDepositedWethAndMintedOsc
        daveApprovesOsc
    {
        vm.startPrank(DAVE);
        osce.mintOsc(18000);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(NEW_ETH_PRICE);

        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BreaksHealthFactor.selector, 4e17));
        osce.liquidate(USER, 2000, weth);
        vm.stopPrank();
    }

    //Getter Tests
    function testUserCanGetTotalCollateralValueInUsdDeposited() public userDepositedWeth {
        uint256 expectedValue = 8000e18;
        vm.prank(USER);
        uint256 actualValue = osce.getTotalCollateralValueInUsdDeposited(USER);

        assertEq(expectedValue, actualValue);
    }

    function testUserCanGetHealthFactorEvenWhenMintedOscIsZero() public userDepositedWeth {
        vm.prank(USER);
        uint256 healthFactor = osce.getUserHealthFactor(USER);
        assert(healthFactor > 1);
    }

    function testUserCanGetCollateralTokens() public userDepositedWeth {
        address[] memory tokenAddresses = osce.getCollateralTokenAddresses();
        assert(tokenAddresses.length == 2);
    }
}
