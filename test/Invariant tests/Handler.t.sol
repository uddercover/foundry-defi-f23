//SPDX-License-Identifier: MIT

/*
* Our Invariants:
* We want to always have mo
* We want view functions to never revert
*/
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {OrenjiStableCoin} from "../../src/OrenjiStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    OSCEngine osce;
    OrenjiStableCoin osc;
    address weth;
    address wbtc;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(OSCEngine _oscEngine, OrenjiStableCoin _osc) {
        osce = _oscEngine;
        osc = _osc;

        address[] memory tokens = osce.getCollateralTokenAddresses();
        weth = tokens[0];
        wbtc = tokens[1];
    }
    //for depositCollateral: Only call with allowed collaterals
    //for redeemCollateral: Only redeem if there is collateral to redeem

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address token = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);
        ERC20Mock(token).mint(msg.sender, amountCollateral);
        ERC20Mock(token).approve(address(osce), amountCollateral);

        osce.depositCollateral(token, amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address token = _getCollateralFromSeed(collateralSeed);
        uint256 maxRedeemableByUser = osce.getCollateralDepositedByUser(token, msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxRedeemableByUser);
        if (amountCollateral == 0) {
            return;
        }

        osce.redeemCollateral(token, amountCollateral);
    }

    //helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
