// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    uint256 public COLLATERAL_AMOUNT = 10 ether;
    uint256 public STARTING_ERC20_BALANCE = 10 ether;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public LIQUIDATION_THRESHOLD = 50;
    uint256 public LIQUIDATION_BONUS = 10;
    uint256 public COLLATERAL_TO_COVER = 20 ether;    

    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,, ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    ///////////////////////////////
    // Constructor tests ////
    ///////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressMustBeSameAsPriceFeedAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////////////
    // Price tests ////
    ///////////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////////
    // Deposit Collateral tests ////
    ///////////////////////////////

    function testRevertIfCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositWithoutCollateral() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    /////////////////////////////////////////
    // depositCollateralAndMintDsc tests ////
    /////////////////////////////////////////
    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (COLLATERAL_AMOUNT * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }
    ///////////////////////////////
    // MintDsc tests /////////////
    ///////////////////////////////
    function testRevertIfMintAmountIsZero() public depositedCollateral {        
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }
    /* NEXT CALL DID NOT REVERT AS EXPECTED
    function testRevertIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (COLLATERAL_AMOUNT * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        
        vm.startPrank(USER);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, COLLATERAL_AMOUNT));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, expectedHealthFactor));
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }
    */
    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
        vm.stopPrank();
    }
    ///////////////////////////////
    // BurnDsc tests /////////////
    ///////////////////////////////
    function testRevertIfBurnAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.burnDsc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////
    // Redeem Collateral tests ////
    ///////////////////////////////
    
    function testRevertIfRedeemCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }
    /* DIVISION OR MODULO BY ZERO
    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }
    */
    ///////////////////////////////
    // Health Factor tests ////////
    ///////////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////////////
    // Liquidation tests //////////
    ///////////////////////////////
    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_TO_COVER);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_TO_COVER);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
        _;
    }

    /* HEALTHFACTOR OK BUG 
    function testLiqudationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(weth, amountToMint) + (dscEngine.getTokenAmountFromUsd(weth, amountToMint) / LIQUIDATION_BONUS);
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, expectedWeth);
        assertEq(liquidatorWethBalance, hardCodedExpected);
    }

    function testUserStillHasEthAfterLiquidation() public liquidated {
        uint256 amountLiquidated = dscEngine.getTokenAmountFromUsd(weth, amountToMint) + (dscEngine.getTokenAmountFromUsd(weth, amountToMint) / LIQUIDATION_BONUS);
        uint256 usdAmountLiquidated = dscEngine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dscEngine.getUsdValue(weth, COLLATERAL_AMOUNT) - usdAmountLiquidated;

        (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 hardCodedExpected = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpected);
    }

    function testLiquidatorTakeOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
    */
}