// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author John Caraballo
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1:1 peg to the US Dollar.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * IT is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be overcollateralized. At no point, should the value of all collateral <= the $ backed value of all the DSC.
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////
    // ERRORS //
    ///////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__NotAllowedCollateral(address tokenCollateralAddress);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();

    ///////////////
    // STATE VARIABLES //
    ///////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    mapping(address token => address priceFeed) private s_priceFeeds; // Maps token address to price feed address
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits; // Maps user address to their collateral deposits
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // Maps user address to the amount of DSC they have minted
    address[] private s_allowedCollateralTokens; // List of allowed collateral tokens

    DecentralizedStableCoin private immutable i_dsc; // The stablecoin that this system manages

    ///////////////
    // EVENTS //
    //////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

    ///////////////
    // MODIFIERS //
    //////////////
    modifier moreThanZero(uint256 amount) {
        require(amount > 0, DSCEngine__MustBeMoreThanZero());
        _;
    }

    modifier isAllowedCollateral(address tokenCollateralAddress) {
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedCollateral(tokenCollateralAddress);
        }
        _;
    }

    ///////////////
    // FUNCTIONS //
    ///////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address tokenAddress = tokenAddresses[i];
            address priceFeed = priceFeedAddress[i];

            if (tokenAddress == address(0) || priceFeed == address(0)) {
                revert DSCEngine__NotAllowedCollateral(tokenAddress);
            }

            s_priceFeeds[tokenAddress] = priceFeed;
            s_allowedCollateralTokens.push(tokenAddress);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////
    // EXTERNAL FUNCTIONS //
    ///////////////
    function depositCollateralAndMintDsc() external {}

    function redeemCollateralForDsc() external {}

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
    {
        s_collateralDeposits[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        require(success, DSCEngine__TransferFailed());
    }

    function redeemCollateral() external {}

    /**
     *
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function mints DSC for the user, given that they have enough collateral deposited.
     */
    function mintDsc(uint256 amountDscToMint) external nonReentrant moreThanZero(amountDscToMint) {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////
    // PRIVATE & INTERNAL VIEW FUNCTIONS //
    ///////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        // 1. Get the total amount of DSC minted by the user
        // 2. Get the total value of collateral deposited by the user
        // 3. Return both values
        totalDscMinted = s_dscMinted[user];
        totalCollateralValue = getAccountCollateralValue(user);
    }

    /**
     * @notice Calculates the health factor for a user.
     * @param user The address of the user to calculate the health factor for.
     * @return How close the user is to liquidation.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        // 1. Get the total value of collateral
        // 2. Get the total value of DSC minted
        // 3. Calculate health factor = total collateral value / total DSC value
        // 4. Return health factor
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health factor
        // 2. Revert if health factor is broken
    }

    ///////////////
    // PUBLIC & EXTERNAL VIEW FUNCTIONS //
    ///////////////
    function getUsdValue(address tokenAddress, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 allowedCollateralTokens = s_allowedCollateralTokens.length;
        for (uint256 i = 0; i < allowedCollateralTokens; i++) {
            address tokenAddress = s_allowedCollateralTokens[i];
            uint256 amountCollateral = s_collateralDeposits[user][tokenAddress];
            if (amountCollateral > 0) {
                // Get the price of the collateral token in USD
                uint256 collateralValueInUsd = getUsdValue(tokenAddress, amountCollateral);
                totalCollateralValueInUsd += collateralValueInUsd;
            }
        }

        return totalCollateralValueInUsd;
    }
}
