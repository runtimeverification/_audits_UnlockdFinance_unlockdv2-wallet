// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {DelegationOwner, DelegationWalletFactory, TestNft, Config} from "./utils/Config.sol";

import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { GuardOwner } from "../src/libs/owners/GuardOwner.sol";

contract DelegationWalletFactoryTest is Config {
    function setUp() public {
        vm.prank(kakaroto);
        (safeProxy, delegationOwnerProxy, protocolOwnerProxy, guardOwnerProxy) = delegationWalletFactory.deploy(delegationController);
        safe = GnosisSafe(payable(safeProxy));
    }

    function test_deploy_should_work() public {
        assertEq(safe.getThreshold(), 1);
        address guard = address(GuardOwner(guardOwnerProxy).guard());
        address[] memory owners = safe.getOwners();

        assertEq(owners.length, 4);
        assertEq(owners[0], kakaroto);
        assertEq(owners[1], guardOwnerProxy);
        assertEq(owners[2], delegationOwnerProxy);
        assertEq(owners[3], protocolOwnerProxy);

        bytes memory storageAt = safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1);
        address configuredGuard = abi.decode(storageAt, (address));
        assertEq(configuredGuard, guard);

        assertEq(DelegationOwner(delegationOwnerProxy).owner(), address(kakaroto));
        assertEq(address(DelegationOwner(delegationOwnerProxy).guard()), configuredGuard);
        assertEq(DelegationOwner(delegationOwnerProxy).safe(), safeProxy);
        assertTrue(DelegationOwner(delegationOwnerProxy).delegationControllers(delegationController));
    }

    function test_deploy_should_work_with_zero_controllers() public {
        (address _safeProxy,  address _delegationOwner, address _productOwner, ) = delegationWalletFactory
            .deployFor(vegeta, address(0));

        assertEq(DelegationOwner(_delegationOwner).owner(), vegeta);
        assertEq(DelegationOwner(_delegationOwner).aclManager(), address(aclManager));
    }
}
