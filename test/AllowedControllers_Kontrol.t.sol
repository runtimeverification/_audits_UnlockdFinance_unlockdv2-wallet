// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import {AllowedControllers, Errors} from "src/libs/allowed/AllowedControllers.sol";
import { ACLManager } from "./mocks/ACLManager.sol";
import {KontrolCheats} from "lib/kontrol-cheatcodes/src/KontrolCheats.sol";

contract KontrolAllowedControllersTest is Test, KontrolCheats {
    address initManager;
    address admin;

    ACLManager public aclManager;
    AllowedControllers public allowedControllers;

    function setUp() public {
        initManager = makeAddr("manager");
        aclManager = new ACLManager(initManager);
        allowedControllers = new AllowedControllers(address(aclManager), new address[](0));

        admin = kevm.freshAddress();

        vm.startPrank(initManager);
        aclManager.addGovernanceAdmin(admin);
        aclManager.addProtocolAdmin(admin);
        vm.stopPrank();
    }

    function _notBuiltinAddress(address addr) internal view {
        vm.assume(addr != address(this));
        vm.assume(addr != address(vm));
        vm.assume(addr != address(aclManager));
        vm.assume(addr != address(allowedControllers));
        vm.assume(addr != initManager);
    }

    function prove_setCollectionAllowance_invalid(address collection, address caller) public {
        _notBuiltinAddress(caller);

        vm.assume(collection == address(0));
        vm.prank(caller);

        // `Errors.Caller_notGovernanceAdmin.selector` or `Errors.AllowedCollections__setCollectionsAllowances_invalidAddress.selector`
        vm.expectRevert();
        allowedControllers.setCollectionAllowance(collection, true);
    }


    /*
    function test_setCollectionAllowance_onlyGovernance() public {
        address caller = kevm.freshAddress();

        vm.expectRevert(Errors.Caller_notGovernanceAdmin.selector);
        allowedControllers.setCollectionAllowance(karpincho, true);
    }

    function test_setCollectionAllowance_invalidAddress() public {
        vm.prank(kakaroto);
        vm.expectRevert(Errors.AllowedCollections__setCollectionsAllowances_invalidAddress.selector);
        allowedControllers.setCollectionAllowance(address(0), true);
    }
    */

    function test_setCollectionAllowance_valid(address collection) public {
        vm.assume(collection != address(0));
        _notBuiltinAddress(admin);
        
        vm.prank(admin);

        allowedControllers.setCollectionAllowance(collection, true);
        assertTrue(allowedControllers.isAllowedCollection(collection));

        vm.prank(admin);

        allowedControllers.setCollectionAllowance(collection, false);
        assertFalse(allowedControllers.isAllowedCollection(collection));
    }

    /*

    function test_setCollectionAllowance_should_work() public {
        vm.prank(kakaroto);

        allowedControllers.setCollectionAllowance(karpincho, true);
        assertTrue(allowedControllers.isAllowedCollection(karpincho));

        vm.prank(kakaroto);

        allowedControllers.setCollectionAllowance(karpincho, false);
        assertFalse(allowedControllers.isAllowedCollection(karpincho));
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


    /*
    /// @custom:kontrol-array-length-equals _delegationControllers: 2,
    function prove_setDelegationControllerAllowances(address[] memory _delegationControllers) public {
        uint256 i;
        bool[] memory _allowances = new bool[](_delegationControllers.length);

        for (i = 0; i < _delegationControllers.length;) {
            vm.assume(_delegationControllers[i] != address(0));
            _allowances[i] = true;

            unchecked {
                i++;
            }
        }

        _notBuiltinAddress(admin);
        vm.prank(admin);


        allowedControllers.setDelegationControllerAllowances(_delegationControllers, _allowances);

        for (i = 0; i < _delegationControllers.length;) {
            assert(allowedControllers.isAllowedDelegationController(_delegationControllers[i]));
            unchecked {
                i++;
            }
        }
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
    */
}
