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

/*
 *@title DecentralizedStableCoin
 *@author Uddercover
 *@notice This contract creates and regulates a cryptocurrency with minimal price flunctuations
 *@dev This contract is meant to be governed by DSCEngine. 
       This contract is just the ERC20 implementation of the stablecoin system
  *Collateral: Exogenous (ETH BTC)
  *Relative Stability: Pegged to USD
  *Stability Mechanism(Minting): Algorithmic
 */
contract DecentralizedStableCoin {}
