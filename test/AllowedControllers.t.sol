// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {AllowedControllers, Errors} from "src/libs/allowed/AllowedControllers.sol";
import {Config} from "./utils/Config.sol";

contract AllowedControllersTest is Config {
    function test_should_set_controllers_upon_creation(address[] memory _delegationControllers) public {
        uint256 i;

        for (i = 0; i < _delegationControllers.length;) {
            vm.assume(_delegationControllers[i] != address(0));
            unchecked {
                i++;
            }
        }

        AllowedControllers allowed = new AllowedControllers(address(aclManager), _delegationControllers);

        for (i = 0; i < _delegationControllers.length;) {
            assertTrue(allowed.isAllowedDelegationController(_delegationControllers[i]));
            unchecked {
                i++;
            }
        }
    }

    function test_setCollectionAllowance_onlyGovernance() public {
        vm.prank(karpincho);
        vm.expectRevert(Errors.Caller_notGovernanceAdmin.selector);
        allowedControllers.setCollectionAllowance(karpincho, true);
    }

    function test_setCollectionAllowance_invalidAddress() public {
        vm.prank(kakaroto);
        vm.expectRevert(Errors.AllowedCollections__setCollectionsAllowances_invalidAddress.selector);
        allowedControllers.setCollectionAllowance(address(0), true);
    }

    function test_setCollectionAllowance_should_work() public {
        vm.prank(kakaroto);

        allowedControllers.setCollectionAllowance(karpincho, true);
        assertTrue(allowedControllers.isAllowedCollection(karpincho));

        vm.prank(kakaroto);

        allowedControllers.setCollectionAllowance(karpincho, false);
        assertFalse(allowedControllers.isAllowedCollection(karpincho));
    }

    function test_setCollectionAllowances_onlyGov() public {
        address[] memory controllers = new address[](1);
        controllers[0] = karpincho;
        bool[] memory allowances = new bool[](1);
        vm.prank(karpincho);
        vm.expectRevert(Errors.Caller_notGovernanceAdmin.selector);
        allowedControllers.setCollectionsAllowances(controllers, allowances);
    }

    function test_setCollectionAllowances_arityMismatch() public {
        address[] memory controllers = new address[](2);
        controllers[0] = kakaroto;
        controllers[1] = vegeta;
        bool[] memory allowances = new bool[](1);
        allowances[0] = true;

        vm.prank(kakaroto);

        vm.expectRevert(Errors.AllowedCollections__setCollectionsAllowances_arityMismatch.selector);
        allowedControllers.setCollectionsAllowances(controllers, allowances);
    }

    function test_setCollectionAllowances_invalidAddress() public {
        address[] memory controllers = new address[](1);
        controllers[0] = address(0);
        bool[] memory allowances = new bool[](1);
        allowances[0] = true;
        vm.prank(kakaroto);

        vm.expectRevert(Errors.AllowedCollections__setCollectionsAllowances_invalidAddress.selector);
        allowedControllers.setCollectionsAllowances(controllers, allowances);
    }

    function test_setCollectionAllowances_should_work() public {
        address[] memory controllers = new address[](2);
        controllers[0] = kakaroto;
        controllers[1] = karpincho;
        bool[] memory allowances = new bool[](2);
        allowances[0] = true;
        allowances[1] = true;

        vm.prank(kakaroto);

        allowedControllers.setCollectionsAllowances(controllers, allowances);

        for (uint256 i; i < controllers.length;) {
            assertEq(allowedControllers.isAllowedCollection(controllers[i]), allowances[i]);
            unchecked {
                i++;
            }
        }
    }

    function test_setDelegationControllerAllowance_onlyOwner() public {
        vm.prank(karpincho);
        vm.expectRevert(Errors.Caller_notAdmin.selector);
        allowedControllers.setDelegationControllerAllowance(karpincho, true);
    }

    function test_setDelegationControllerAllowance_invalidAddress() public {
        vm.prank(kakaroto);
        vm.expectRevert(Errors.AllowedControllers__setDelegationControllerAllowance_invalidAddress.selector);
        allowedControllers.setDelegationControllerAllowance(address(0), true);
    }

    function test_setDelegationControllerAllowance_should_work() public {
        vm.prank(kakaroto);

        allowedControllers.setDelegationControllerAllowance(karpincho, true);
        assertTrue(allowedControllers.isAllowedDelegationController(karpincho));

        vm.prank(kakaroto);

        allowedControllers.setDelegationControllerAllowance(karpincho, false);
        assertFalse(allowedControllers.isAllowedDelegationController(karpincho));
    }

    function test_setDelegationControllerAllowances_onlyAdmin() public {
        address[] memory controllers = new address[](1);
        controllers[0] = karpincho;
        bool[] memory allowances = new bool[](1);
        vm.prank(karpincho);
        vm.expectRevert(Errors.Caller_notAdmin.selector);
        allowedControllers.setDelegationControllerAllowances(controllers, allowances);
    }

    function test_setDelegationControllerAllowances_arityMismatch() public {
        address[] memory controllers = new address[](2);
        controllers[0] = kakaroto;
        controllers[1] = vegeta;
        bool[] memory allowances = new bool[](1);
        allowances[0] = true;
        vm.prank(kakaroto);

        vm.expectRevert(Errors.AllowedControllers__setDelegationControllerAllowances_arityMismatch.selector);
        allowedControllers.setDelegationControllerAllowances(controllers, allowances);
    }

    function test_setDelegationControllerAllowances_invalidAddress() public {
        address[] memory controllers = new address[](1);
        controllers[0] = address(0);
        bool[] memory allowances = new bool[](1);
        allowances[0] = true;
        vm.prank(kakaroto);

        vm.expectRevert(Errors.AllowedControllers__setDelegationControllerAllowance_invalidAddress.selector);
        allowedControllers.setDelegationControllerAllowances(controllers, allowances);
    }

    function test_setDelegationControllerAllowances_should_work() public {
        address[] memory controllers = new address[](2);
        controllers[0] = kakaroto;
        controllers[1] = karpincho;
        bool[] memory allowances = new bool[](2);
        allowances[0] = true;
        allowances[1] = true;
        vm.prank(kakaroto);

        allowedControllers.setDelegationControllerAllowances(controllers, allowances);

        for (uint256 i; i < controllers.length;) {
            assertEq(allowedControllers.isAllowedDelegationController(controllers[i]), allowances[i]);
            unchecked {
                i++;
            }
        }
    }
}
