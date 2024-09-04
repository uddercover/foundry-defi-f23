//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.1;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/*
 *@title OrenjiStableCoin
 *@author Uddercover
 *@notice This contract creates and regulates a cryptocurrency with minimal price flunctuations
 *@dev This contract is meant to be governed by OSCEngine. 
       This contract is just the ERC20 implementation of the stablecoin system
  *Collateral: Exogenous (ETH BTC)
  *Relative Stability: Pegged to USD
  *Stability Mechanism(Minting): Algorithmic
 */

contract OrenjiStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("OrenjiStableCoin", "OSC") Ownable(msg.sender) {}

    error OrenjiStableCoin__CantMintToZeroAddress();
    error OrenjiStableCoin__AmountMustBeGreaterThanZero();
    error OrenjiStableCoin__BalanceMustBeGreaterThanZero();

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert OrenjiStableCoin__CantMintToZeroAddress();
        }
        if (_amount <= 0) {
            revert OrenjiStableCoin__AmountMustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount == 0) {
            revert OrenjiStableCoin__AmountMustBeGreaterThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert OrenjiStableCoin__BalanceMustBeGreaterThanZero();
        }
        super.burn(_amount);
    }
}
