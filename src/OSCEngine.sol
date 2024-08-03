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

import {OrenjiStableCoin} from "./OrenjiStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

contract OSCEngine is ReentrancyGuard {
    //////////////////
    // ERRORS     ////
    //////////////////
    error OSCEngine__MustBeMoreThanZero();
    error OSCEngine__ZeroAddressNotAllowed();
    error OSCEngine__CollateralNotAllowed();
    error OSCEngine__MustDepositAtLeastMinimumCollateral();
    error OSCEngine__CollateralAddressesAndPriceFeedAddressesMustBeSameLength();
    error OSCEngine__TransferFailed();

    /////////////////////////////
    // TYPE DECLARATIONS     ////
    /////////////////////////////

    /////////////////////////////
    // STATE VARIABLES       ////
    /////////////////////////////
    OrenjiStableCoin private immutable i_orenjiStableCoin;
    uint256 constant DECIMALPRECISIONVALUE = 1e10;
    uint256 constant WEIDECIMALPRECISIONVALUE = 1e18;
    uint256 minimumCollateralBTC;
    uint256 minimumCollateralETH;
    mapping(address collateralAddress => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateral => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 OSCminted) private s_OSCMinted;
    address[] private s_collateralAddresses;

    /////////////////////////////
    // EVENTS                ////
    /////////////////////////////
    event CollateralDeposited(
        address indexed depositer, address indexed collateralAddress, uint256 indexed amountDeposited
    );

    /////////////////////////////
    // MODIFIERS             ////
    /////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert OSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    /*
    * Necessary in case a user passes in a collateral address that's not allowed
    */
    modifier isAllowedCollateral(address collateral) {
        if (s_priceFeeds[collateral] == address(0)) {
            revert OSCEngine__CollateralNotAllowed();
        }
        _;
    }

    /////////////////////////////
    // FUNCTIONS             ////
    /////////////////////////////
    constructor(address[] memory collateralAddresses, address[] memory priceFeedAddresses, address stableCoinAddress) {
        if (collateralAddresses.length > priceFeedAddresses.length) {
            revert OSCEngine__CollateralAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            s_priceFeeds[collateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralAddresses.push(collateralAddresses[i]);
        }
        //s_priceFeeds(address(0)) = address(0); //placeholders: zero address
        //s_priceFeeds(address(0)) = address(0);
        i_orenjiStableCoin = OrenjiStableCoin(stableCoinAddress);
    }

    /////////////////////////////
    // EXTERNAL FUNCTIONS    ////
    /////////////////////////////

    /*
     * @notice follows CEI
     * @param amountToBeMinted is the amount a user wants to mint
    */
    function mint(uint256 amountToBeMinted) external moreThanZero(amountToBeMinted) nonReentrant {
        /*Checks
        Retrieve total collateral deposited by user
            for each token collateral type, get the value deposited by user
            get the usd value
            sum them up

        Ensure that amountToBeMinted falls within the range for healthFactor to be stable
            specify the healthfactor (and all the calculations to keep it stable)
        */

        /*Effects
        mint tokens based on value of collateral 
            Get the 1 usd equivalent of collateral
                get the eth/usd and btc/usd pricefeed contracts from chainlink

            Check that each token is minted according to the above
        */
        //mapping update
        s_OSCMinted[msg.sender] += amountToBeMinted;

        //actual mint
        /*Interactions
        //orenjiStableCoin.mint();
        */
        //Would likely go into the health factor check function
        uint256 totalCollateralValueInUsdDepositedByUser = getTotalCollateralValueInUsdDeposited(msg.sender);
        //healthfactor check based on collateral deposited
        _revertIfHealthFactorIsBroken(msg.sender, amountToBeMinted);
    }

    function burn() external {}

    function depositCollateraltoMintOsc() external {}

    /*
     *@notice follows CEI (Checks, Effects, Interactions)
     *@param tokenCollateralAddress The address of the collateral
     *@param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        //Checks
        /*if (tokenCollateralAddress == address(0)) {
            revert OSCEngine__ZeroAddressNotAllowed();
        }

        if (s_priceFeeds[tokenCollateralAddress] == s_priceFeeds[]) {
            if (amountCollateral < minimumCollateralETH) {
                revert OSCEngine__MustDepositAtLeastMinimumCollateral();
            }
        }
        if (tokenCollateralAddress == allowedCollateral["BTC"]) {
            if (amountCollateral < minimumCollateralBTC) {
                revert OSCEngine__MustDepositAtLeastMinimumCollateral();
            }
        }
        */
        //Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForOsc() external {}

    function redeemCollateral() external {}

    function liquidate() external {}

    function healthFactor() external {}

    ////////////////////////
    // PUBLIC FUNCTIONS ///
    //////////////////////
    function getUserAccountInformation(address user)
        public
        returns (uint256 totalOSCMinted, uint256 collateralValueInUsd)
    {
        (totalOSCMinted, collateralValueInUsd) = _getUserAccountInformation(user);
    }

    //////////////////////////////////////////
    // PUBLIC AND EXTERNAL VIEW FUNCTIONS ///
    ////////////////////////////////////////

    function getTotalCollateralValueInUsdDeposited(address user)
        public
        view
        returns (uint256 collateralDepositedByUser)
    {
        collateralDepositedByUser = _getTotalCollateralValueInUsdDeposited(user);
    }

    /////////////////////////////////
    // INTERNAL VIEW FUNCTIONS //////
    ///////////////////////////////
    function _revertIfHealthFactorIsBroken(address user, uint256 amount) internal view {
        //check if they have enough health factor, revert if they don't
    }

    function _getTotalCollateralValueInUsdDeposited(address user)
        internal
        view
        returns (uint256 collateralDepositedByUser)
    {
        //for each token collateral type, get the value deposited by user, get the usd value, sum them up
        for (uint256 i; i < s_collateralAddresses.length; i++) {
            collateralDepositedByUser +=
                _usdValueOfCollateral(s_collateralDeposited[user][s_collateralAddresses[i]], s_collateralAddresses[i]);
        }
    }

    ////////////////////////////
    // PRIVATE FUNCTIONS //////
    //////////////////////////

    function _getUserAccountInformation(address user)
        private
        view
        returns (uint256 totalOscMinted, uint256 collateralValueInUsd)
    {
        totalOscMinted = s_OSCMinted[user];
        collateralValueInUsd = _getTotalCollateralValueInUsdDeposited(user);
    }

    /////////////////////////////////
    // PRIVATE VIEW FUNCTIONS //////
    ///////////////////////////////
    function _usdValueOfCollateral(uint256 amount, address collateralAddress) private view returns (uint256) {
        //Use chainlink to get price, multiply price by amount to get usd price of amount. Make sure the decimals are correct
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        //price is an int and is multiplied by 1e8
        //amount is a uint and is multiplied by 1e18
        //match their decimals and type before multiplying
        uint256 usdValue = ((uint256(price) * DECIMALPRECISIONVALUE) * amount) / WEIDECIMALPRECISIONVALUE;
        return usdValue;
    }

    /*
     *Returns how close to liquidation a user is
     *If a user goes below 1, then they can get liquidated
    */
    function _healthFactor() private view returns (uint256) {}
}
