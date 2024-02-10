//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor Tests
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenAddressLengthDoesntMatchPriceFeedAddressLength() external {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Price Tests
    function testGetUsdValue() external {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedAmount = 30000e18;
        uint256 actualAmount = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedAmount, actualAmount);
    }

    function testGetTokenAmountFromUsd() external {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH , $100
        uint256 expectedAmount = 0.05 ether;
        uint256 actualAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedAmount, actualAmount);
    }

    // depositCollateral Tests
    function testRevertsIfCollateralZero() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsForUnapprovedCollateralDeposit() external {
        ERC20Mock newToken = new ERC20Mock("New Token", "NTN", USER, STARTING_ERC20_BALANCE);

        vm.startPrank(USER);
        ERC20Mock(newToken).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(newToken), 5 ether);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() external depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedTokenDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUSD);
        uint256 expectedCollateralValueInUSD = engine.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedTokenDeposited, AMOUNT_COLLATERAL);
        assertEq(expectedCollateralValueInUSD, collateralValueInUSD);
    }

    // mintDsc test
    function testRevertsIfZeroDscToMint() external depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsBrokenWhileMintingDsc() external depositedCollateral {
        uint256 DscToMint = 10001;
        (, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 healthFactor = (collateralAdjustedForThreshold) / DscToMint;

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, healthFactor));
        engine.mintDSC(DscToMint);
        vm.stopPrank();
    }

    function testDscMintedToUser() external depositedCollateral {
        uint256 DscToMint = 10000;

        vm.startPrank(USER);
        engine.mintDSC(DscToMint);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        uint256 UserBalance = dsc.balanceOf(USER);
        assertEq(UserBalance, totalDscMinted);
        assertEq(totalDscMinted, DscToMint);
    }

    // burnDsc test
    function testBurnDsc() external depositedCollateral {
        uint256 DscToMint = 10000;

        vm.startPrank(USER);
        engine.mintDSC(DscToMint);
        ERC20Mock(address(dsc)).approve(address(engine), AMOUNT_COLLATERAL);
        engine.burnDSC(1000);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        uint256 UserBalance = dsc.balanceOf(USER);
        assertEq(UserBalance, totalDscMinted);
        assertEq(totalDscMinted, 9000);
    }

    function testRedeemCollateral() external depositedCollateral {
        uint256 DscToMint = 1000;
        uint256 startingUserBalance = ERC20Mock(weth).balanceOf(USER);

        vm.startPrank(USER);
        engine.mintDSC(DscToMint);
        engine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();

        uint256 endingUserBalance = ERC20Mock(weth).balanceOf(USER);
        // (, uint256 collateralDeposited) = engine.getAccountInformation(USER);

        // assertEq(endingUserBalance, collateralDeposited);
        assertEq(startingUserBalance + 1 ether, endingUserBalance);
    }
}
