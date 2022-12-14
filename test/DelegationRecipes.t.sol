// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import { DelegationOwner, DelegationGuard, DelegationWalletFactory, TestNft, Config, TestNftPlatform } from "./utils/Config.sol";

import { GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DelegationRecipes is Config {
    function setUp() public {
        vm.prank(kakaroto);
        (safeProxy, delegationOwnerProxy, delegationGuardProxy) = delegationWalletFactory.deploy(address(this), nftfi);
        safe = GnosisSafe(payable(safeProxy));
    }

    function test_add_should_work() public {
        assertTrue(delegationRecipes.isAllowedFunction(address(testNft), address(testNftPlatform), TestNftPlatform.allowedFunction.selector));
        assertEq(delegationRecipes.functionDescriptions(keccak256(abi.encodePacked(address(testNft), address(testNftPlatform), TestNftPlatform.allowedFunction.selector))), "TestNftPlatform - allowedFunction");
    }

    function test_remove_should_work() public {
        address[] memory contracts = new address[](1);
        bytes4[] memory selectors = new bytes4[](1);
        contracts[0] = address(testNftPlatform);
        selectors[0] = TestNftPlatform.allowedFunction.selector;
        delegationRecipes.remove(address(testNft), contracts, selectors);

        assertFalse(delegationRecipes.isAllowedFunction(address(testNft), address(testNftPlatform), TestNftPlatform.allowedFunction.selector));
        assertEq(delegationRecipes.functionDescriptions(keccak256(abi.encodePacked(address(testNft), address(testNftPlatform), TestNftPlatform.allowedFunction.selector))), "");
    }
}
