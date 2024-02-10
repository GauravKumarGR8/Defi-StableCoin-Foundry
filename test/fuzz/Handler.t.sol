// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralisedStableCoin dsc;

    address weth;
    address wbtc;
    address[] public usersWithCollateral;

    uint256 MAX_DEPOSITED = type(uint96).max;

    uint256 public mintDscCalled;

    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];
    }

    function mintDsc(uint256 amount /* uint256 userSeed */ ) public {
        // if (usersWithCollateral.length == 0) {
        //     return;
        // }

        // address sender = usersWithCollateral[userSeed % usersWithCollateral.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(address(this));

        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }

        // vm.startPrank(sender);
        engine.mintDSC(amount);
        // vm.stopPrank();
        // mintDscCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSITED);

        // vm.startPrank(msg.sender);
        // ERC20Mock(collateral).mint(msg.sender, MAX_DEPOSITED);
        ERC20Mock(collateral).mint(address(this), MAX_DEPOSITED);
        ERC20Mock(collateral).approve(address(engine), MAX_DEPOSITED);
        engine.depositCollateral(collateral, amountCollateral);
        // vm.stopPrank();

        // usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        // uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, collateral);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(address(this), collateral);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        engine.redeemCollateral(collateral, amountCollateral);
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
