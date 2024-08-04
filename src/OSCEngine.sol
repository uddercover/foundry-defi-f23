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
    error OSCEngine__BreaksHealthFactor(uint256);

    /////////////////////////////
    // TYPE DECLARATIONS     ////
    /////////////////////////////

    /////////////////////////////
    // STATE VARIABLES       ////
    /////////////////////////////
    OrenjiStableCoin private immutable i_orenjiStableCoin;
    uint256 constant DECIMALPRECISIONVALUE = 1e10;
    uint256 constant WEIDECIMALPRECISIONVALUE = 1e18;
    uint256 constant LIQUIDATION_THRESHOLD = 50; //that is 50% of collateral
    uint256 constant LIQUIDATION_PRECISION = 100; // that is 100%
    uint256 minimumCollateralETH;

    mapping(address collateralAddress => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateral => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOscminted) private s_OSCMinted;
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

    //////////////////////////////
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
     * @param amountToBeMinted is the amount a user wants to mint
     * @notice follows CEI
     * @notice they must have more collateral than amountToBeMinted

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

        //healthfactor check based on collateral deposited
        _revertIfHealthFactorIsBroken(msg.sender);
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

    function oscAvailableToBeMintedBasedOnHealthFactor(address user) external returns (uint256) {}

    ////////////////////////
    // PUBLIC FUNCTIONS ///
    //////////////////////

    ////////////////////////////
    // PRIVATE FUNCTIONS //////
    //////////////////////////

    function _getUserAccountInformation(address user)
        private
        view
        returns (uint256 totalOscMinted, uint256 totalCollateralValueInUsd)
    {
        totalOscMinted = s_OSCMinted[user];
        totalCollateralValueInUsd = _getTotalCollateralValueInUsdDeposited(user);
    }

    //////////////////////////////////////////
    // PUBLIC AND EXTERNAL VIEW FUNCTIONS ///
    ////////////////////////////////////////
    function getUserAccountInformation(address user)
        external
        view
        returns (uint256 totalOSCMinted, uint256 collateralValueInUsd)
    {
        (totalOSCMinted, collateralValueInUsd) = _getUserAccountInformation(user);
    }

    function getTotalCollateralValueInUsdDeposited(address user)
        external
        view
        returns (uint256 totalCollateralValueInUsdDepositedByUser)
    {
        totalCollateralValueInUsdDepositedByUser = _getTotalCollateralValueInUsdDeposited(user);
    }

    function getUsdValueOfCollateral(address collateralAddress, uint256 amount) external view returns (uint256 value) {
        value = _usdValueOfCollateral(collateralAddress, amount);
    }

    /////////////////////////////////
    // INTERNAL VIEW FUNCTIONS //////
    ///////////////////////////////

    /////////////////////////////////
    // PRIVATE VIEW FUNCTIONS //////
    ///////////////////////////////

    function _getTotalCollateralValueInUsdDeposited(address user)
        private
        view
        returns (uint256 totalCollateralValueDepositedByUser)
    {
        //for each token collateral type, get the value deposited by user, get the usd value, sum them up
        for (uint256 i = 0; i < s_collateralAddresses.length; i++) {
            address collateralAddress = s_collateralAddresses[i];
            uint256 amount = s_collateralDeposited[user][collateralAddress];

            totalCollateralValueDepositedByUser += _usdValueOfCollateral(collateralAddress, amount);
        }
    }

    function _usdValueOfCollateral(address collateralAddress, uint256 amount) private view returns (uint256 usdValue) {
        //Use chainlink to get price, multiply price by amount to get usd price of amount. Make sure the decimals are correct
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        /*price is an int and is multiplied by 1e8
         *amount is a uint and is multiplied by 1e18
         *match their decimals and type before multiplying
         *Also, this is just for eth. It isn't modular and doesn't even account for btc precision.
          It needs to be refactored.
        */
        usdValue = ((uint256(price) * DECIMALPRECISIONVALUE) * amount) / WEIDECIMALPRECISIONVALUE;
    }

    /*
     *Returns how close to liquidation a user is
     *If a user goes below 1, then they can get liquidated
    */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalOscMinted, uint256 totalCollateralValueInUsd) = _getUserAccountInformation(user);

        //essentially multiplied by 0.5 but solidity can't do decimals unfortunately :(
        uint256 adjustedCollateralValueInUsd =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        /*to ensure that to stay above liquidation, the user must deposit double(depending on the liquidation threshold) the collateral value per osc minted
        Essentially, healthFactor should not fall below 1;
        */
        healthFactor = adjustedCollateralValueInUsd / totalOscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        //check if they have enough health factor, revert if they don't
        //get the health factor/amount osc left to be minted based on collateral value
        //if this value is >= amount, allow access, else revert
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < 1) {
            revert OSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
