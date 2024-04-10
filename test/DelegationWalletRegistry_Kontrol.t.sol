// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IDelegationWalletRegistry, DelegationWalletRegistry, Errors} from "../src/DelegationWalletRegistry.sol";

contract DelegationWalletRegistryTest is Test {
    DelegationWalletRegistry internal registry;

    function setUp() public {
        registry = new DelegationWalletRegistry();
    }

    function _notBuiltinAddress(address addr) internal view {
        vm.assume(addr != address(this));
        vm.assume(addr != address(vm));
        vm.assume(addr != address(registry));
    }

    function prove_setFactory_onlyOwner(address caller, address _delegationWalletFactory) public {
        _notBuiltinAddress(caller);
        _notBuiltinAddress(_delegationWalletFactory);

        vm.prank(caller);
        
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setFactory(_delegationWalletFactory);
    }

    function prove_setFactory_should_work(address _delegationWalletFactory) public {
        _notBuiltinAddress(_delegationWalletFactory);
        vm.assume(_delegationWalletFactory != address(0));

        registry.setFactory(_delegationWalletFactory);

        assert(registry.delegationWalletFactory() == _delegationWalletFactory);
    }
}
