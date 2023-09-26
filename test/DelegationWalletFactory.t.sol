// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, DelegationGuard, DelegationWalletFactory, TestNft, Config } from "./utils/Config.sol";

import { GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DelegationWalletFactoryTest is Config {
    function setUp() public {
        vm.prank(kakaroto);
        (safeProxy, delegationOwnerProxy, delegationGuardProxy, protocolOwnerBeacon) = delegationWalletFactory.deploy(delegationController);
        safe = GnosisSafe(payable(safeProxy));
    }

    function test_deploy_should_work() public {
        assertEq(safe.getThreshold(), 1);

        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 3);
        assertEq(owners[0], kakaroto);
        assertEq(owners[1], delegationOwnerProxy);
        assertEq(owners[2], protocolOwnerBeacon);

        bytes memory storageAt = safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1);
        address configuredGuard = abi.decode(storageAt, (address));
        assertEq(configuredGuard, delegationGuardProxy);

        assertEq(DelegationOwner(delegationOwnerProxy).owner(), kakaroto);
        assertEq(address(DelegationOwner(delegationOwnerProxy).guard()), configuredGuard);
        assertEq(DelegationOwner(delegationOwnerProxy).safe(), safeProxy);
        assertTrue(DelegationOwner(delegationOwnerProxy).delegationControllers(delegationController));
    }

    function test_depploy_should_work_with_zero_controllers() public {
        (safeProxy, delegationOwnerProxy, delegationGuardProxy, protocolOwnerBeacon) = delegationWalletFactory.deployFor(vegeta, address(0));

        assertEq(DelegationOwner(delegationOwnerProxy).owner(), vegeta);
        assertEq(DelegationOwner(delegationOwnerProxy).aclManager(), address(aclManager));
    }
}
