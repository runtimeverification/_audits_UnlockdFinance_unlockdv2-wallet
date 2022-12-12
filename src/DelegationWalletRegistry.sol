// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { IDelegationWalletRegistry } from "./interfaces/IDelegationWalletRegistry.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DelegationWalletRegistry is IDelegationWalletRegistry, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => Wallet) internal wallets;

    mapping(address => EnumerableSet.AddressSet) internal walletsByOwner;

    /**
     * @notice Address of the DelegationWalletFactory contract.
     */
    address public delegationWalletFactory;

    // ========== Events ===========

    // ========== Custom Errors ===========
    error DelegationWalletRegistry__onlyFactoryOrOwner();

    error DelegationWalletRegistry__setFactory_invalidAddress();

    error DelegationWalletRegistry__setWallet_invalidWalletAddress();
    error DelegationWalletRegistry__setWallet_invalidOwnerAddress();
    error DelegationWalletRegistry__setWallet_invalidDelegationOwnerAddress();
    error DelegationWalletRegistry__setWallet_invalidGuardAddress();

    // ========== Modifiers ===========
    /**
     * @notice This modifier indicates that only the DelegationWalletFactory can execute a given function.
     */
    modifier onlyFactoryOrOwner() {
        if (_msgSender() != delegationWalletFactory && owner() != _msgSender()) revert DelegationWalletRegistry__onlyFactoryOrOwner();
        _;
    }

    function setFactory(address _delegationWalletFactory) external onlyOwner {
        if (_delegationWalletFactory == address(0)) revert DelegationWalletRegistry__setFactory_invalidAddress();
        delegationWalletFactory = _delegationWalletFactory;
    }

    function setWallet(address _wallet, address _owner, address _delegationOwner, address _delegationGuard) external onlyFactoryOrOwner {
        if (_wallet == address(0)) revert DelegationWalletRegistry__setWallet_invalidWalletAddress();
        if (_owner == address(0)) revert DelegationWalletRegistry__setWallet_invalidOwnerAddress();
        if (_delegationOwner == address(0)) revert DelegationWalletRegistry__setWallet_invalidDelegationOwnerAddress();
        if (_delegationGuard == address(0)) revert DelegationWalletRegistry__setWallet_invalidGuardAddress();

        wallets[_wallet] = Wallet(_wallet, _owner, _delegationOwner, _delegationGuard);

        walletsByOwner[_owner].add(_wallet);
    }

    function getWallet(address _wallet) external view returns(Wallet memory) {
      return wallets[_wallet];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function getOwnerWalletAddresses(address _owner) external view returns(address[] memory) {
      return walletsByOwner[_owner].values();
    }

    function getOwnerWalletAt(address _owner, uint256 _index) external view returns(Wallet memory) {
      return wallets[walletsByOwner[_owner].at(_index)];
    }
}
