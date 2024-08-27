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
    error OSCEngine__MintFailed();
    error OSCEngine__HealthFactorIsStable();
    error OSCEngine__HealthFactorNotImproved();

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
    uint256 constant MIN_HEALTH_FACTOR = 1e18;
    uint256 minimumCollateralETH;
    uint256 constant LIQUIDATION_BONUS = 10; // 10%

    mapping(address collateralAddress => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateral => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOscminted) private s_OSCMinted;
    address[] private s_collateralAddresses;

    /////////////////////////////
    // EVENTS                ////
    /////////////////////////////
    event CollateralDeposited(address indexed user, address indexed collateralAddress, uint256 indexed amount);

    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed collateralAddress, uint256 amount
    );

    event OSCBurnt(address indexed from, address indexed onBehalfOf, uint256 indexed amount);
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
    function mintOsc(uint256 amountToBeMinted) public moreThanZero(amountToBeMinted) nonReentrant {
        //Effects
        s_OSCMinted[msg.sender] += amountToBeMinted;
        _revertIfHealthFactorIsBroken(msg.sender);

        //Interactions
        bool minted = i_orenjiStableCoin.mint(msg.sender, amountToBeMinted);
        if (!minted) {
            revert OSCEngine__MintFailed();
        }
    }

    function burnOsc(uint256 amountOscToBurn) public moreThanZero(amountOscToBurn) nonReentrant {
        _burnOsc(msg.sender, msg.sender, amountOscToBurn);
    }

    /*
     *@param tokenCollateralAddress The address of the collateral to be deposited
     *@param amountCollateral The amount of collateral to be deposited
     *@param amountOscToMint The amount of Osc to be minted 
     *@notice This function deposits collateral and mints OSC in one transaction
     */
    function depositCollateralAndMintOsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountOscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintOsc(amountOscToMint);
    }

    /*
     *@notice follows CEI (Checks, Effects, Interactions)
     *@param tokenCollateralAddress The address of the collateral
     *@param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /*
     * @param tokenCollateral The address of desired collateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountOscToBurn The amount of Osc to burn
     * @notice This function burns specified amount of OSC and redeems the corresponding collateral amount
     */
    function redeemCollateralandBurnOsc(address tokenCollateral, uint256 amountCollateral, uint256 amountOscToBurn)
        external
    {
        burnOsc(amountOscToBurn);
        redeemCollateral(tokenCollateral, amountCollateral);
    }

    function redeemCollateral(address tokenCollateral, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateral, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param debtor The user to be liquidated (has broken health factor)
    * @param amountDebtToPay The amount of debt liquidator wants to pay
    * @param tokenCollateralAddress The erc20 collateral address to liquidate from the user
    * @notice This function pays users to liquidate other users with a bad health factor
    * @notice Assumes the system remains at least 200% overcollateralized. A known bug is if the system is 100% or less overcollateralized
    * @notice You can partially liquidate a user
    */
    function liquidate(address debtor, uint256 amountDebtToPay, address tokenCollateralAddress)
        external
        moreThanZero(amountDebtToPay)
        nonReentrant
    {
        //first make sure debtor actually breaks health factor
        uint256 debtorStartingHealthFactor = _healthFactor(debtor);
        if (debtorStartingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert OSCEngine__HealthFactorIsStable();
        }

        //get how much collateral is equal to the debt. 100$ worth of osc = ?? eth
        uint256 collateralAmountFromDebtToPay = getCollateralAmountFromUsd(tokenCollateralAddress, amountDebtToPay);

        //pay the liquidator the collateralAmount + 10% of the debt they covered
        uint256 bonusCollateral = (LIQUIDATION_BONUS * collateralAmountFromDebtToPay) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = collateralAmountFromDebtToPay + bonusCollateral;

        //Now we burn osc and redeem collateral
        _burnOsc(msg.sender, debtor, amountDebtToPay);
        _redeemCollateral(debtor, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);

        //revert if debtor's health factor is worse or unchanged
        uint256 debtorEndHealthFactor = _healthFactor(debtor);
        if (debtorEndHealthFactor <= debtorStartingHealthFactor) {
            revert OSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function oscAvailableToBeMintedBasedOnHealthFactor(address user) external returns (uint256) {}

    ////////////////////////
    // PUBLIC FUNCTIONS ///
    //////////////////////

    /////////////////////////////////////////
    // PRIVATE AND INTERNAL FUNCTIONS //////
    ///////////////////////////////////////
    /*
     * @dev Low-level internal function. Do not call unless function calling is checking for healthFactor being broken after
     */
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amount) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
    }

    function _burnOsc(address from, address onBehalfOf, uint256 amount) private {
        s_OSCMinted[onBehalfOf] -= amount;
        emit OSCBurnt(from, onBehalfOf, amount);
        bool success = IERC20(i_orenjiStableCoin).transferFrom(from, address(this), amount);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
        i_orenjiStableCoin.burn(amount);
    }

    //////////////////////////////////////////
    // PUBLIC AND EXTERNAL VIEW FUNCTIONS ///
    ////////////////////////////////////////
    function getCollateralAmountFromUsd(address collateralAddress, uint256 usdAmountInWei)
        public
        view
        returns (uint256 collateralAmount)
    {
        //Use chainlink to get price, multiply price by amount to get usd price of amount. Make sure the decimals are correct
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        /*
         *the goal is to have the final result in xe18 (wei)
         *price:  an int, multiplied by 1e8
         *amount: a uint, multiplied by 1e18
         *match their decimals and type before dividing

        */
        collateralAmount = ((usdAmountInWei * WEIDECIMALPRECISIONVALUE) / (uint256(price) * DECIMALPRECISIONVALUE));
    }

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

    //////////////////////////////////////////////
    // INTERNAL AND PRIVATE VIEW FUNCTIONS //////
    ////////////////////////////////////////////

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

    function _usdValueOfCollateral(address collateralAddress, uint256 amountInWei)
        private
        view
        returns (uint256 usdValue)
    {
        //Use chainlink to get price, multiply price by amount to get usd price of amount. Make sure the decimals are correct
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        /*
         *the goal is to have the final result in xe18 (wei)
         *price:  an int, multiplied by 1e8
         *amount: a uint, multiplied by 1e18
         *so we have to match their decimals and type before multiplying
         *Also, this is just for eth. It isn't modular and doesn't even account for btc precision.
          It needs to be refactored.

        */
        usdValue = ((uint256(price) * DECIMALPRECISIONVALUE) * amountInWei) / WEIDECIMALPRECISIONVALUE;
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
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert OSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _getUserAccountInformation(address user)
        private
        view
        returns (uint256 totalOscMinted, uint256 totalCollateralValueInUsd)
    {
        totalOscMinted = s_OSCMinted[user];
        totalCollateralValueInUsd = _getTotalCollateralValueInUsdDeposited(user);
    }
}
