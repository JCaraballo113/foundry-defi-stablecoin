// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
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
    mapping(address token => address priceFeed) private s_priceFeeds; // Maps token address to price feed address
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits; // Maps user address to their collateral deposits

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

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
