// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { console } from "forge-std/console.sol";
import { GnosisSafeProxyFactory, GnosisSafeProxy } from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IDelegationWalletRegistry } from "./interfaces/IDelegationWalletRegistry.sol";
import { GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { DelegationOwner } from "./libs/owners/DelegationOwner.sol";
import { ProtocolOwner } from "./libs/owners/ProtocolOwner.sol";

/**
 * @title DelegationWalletFactory
 * @author BootNode
 * @dev Factory contract for deploying and configuring a new Delegation Wallet
 * Deploys a GnosisSafe, a DelegationOwner and a DelegationGuard, sets Safe wallet threshold to 1, the DelegationOwner
 * contract as owner together with the deployer and the DelegationGuard as the Safe's guard.
 */
contract DelegationWalletFactory {
    /**
     * @notice Stores the Safe proxy factory address.
     */
    address public immutable gnosisSafeProxyFactory;
    /**
     * @notice Stores the Safe implementation address.
     */
    address public immutable singleton;
    /**
     * @notice Stores the Safe CompatibilityFallbackHandler address.
     */
    address public immutable compatibilityFallbackHandler;
    /**
     * @notice Stores the DelegationGuard beacon contract address.
     */
    address public immutable guardBeacon;
    /**
     * @notice Stores the DelegationOwner beacon contract address.
     */
    address public immutable ownerBeacon;
    /**
     * @notice Stores the DelegationOwner beacon contract address.
     */
    address public immutable protocolOwnerBeacon;

    address public immutable protocolGuardBeacon;
    /**
     * @notice Stores the DelegationWalletRegistry contract address.
     */
    address public immutable registry;

    event WalletDeployed(
        address indexed safe,
        address indexed owner,
        address indexed delegationOwner,
        address delegationGuard,
        address sender
    );

    constructor(
        address _gnosisSafeProxyFactory,
        address _singleton,
        address _compatibilityFallbackHandler,
        address _guardBeacon,
        address _ownerBeacon,
        address _protocolOwnerBeacon,
        address _protocolGuardBeacon,
        address _registry
    ) {
        gnosisSafeProxyFactory = _gnosisSafeProxyFactory;
        singleton = _singleton;
        compatibilityFallbackHandler = _compatibilityFallbackHandler;
        guardBeacon = _guardBeacon;
        ownerBeacon = _ownerBeacon;
        protocolOwnerBeacon = _protocolOwnerBeacon;
        protocolGuardBeacon = _protocolGuardBeacon;
        registry = _registry;
    }

    /**
     * @notice Deploys a new DelegationWallet with the msg.sender as the owner.
     */
    function deploy(address _delegationController) external returns (address, address, address, address) {
        return deployFor(msg.sender, _delegationController);
    }

    /**
     * @notice Deploys a new DelegationWallet for a given owner.
     * @param _owner - The owner's address.
     * @param _delegationController - Delegation controller owner
     */
    function deployFor(
        address _owner, 
        address _delegationController
    ) public returns (
        address, 
        address, 
        address, 
        address
    ) {
        address safeProxy = address(
            GnosisSafeProxyFactory(gnosisSafeProxyFactory).createProxy(singleton, new bytes(0))
        );

        address delegationOwnerProxy = address(new BeaconProxy(ownerBeacon, new bytes(0)));
        address protocolOwnerProxy = address(new BeaconProxy(protocolOwnerBeacon, new bytes(0)));

        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = delegationOwnerProxy;
        owners[2] = protocolOwnerProxy;

        // setup owners and threshold, this should be done before delegationOwner.initialize because DelegationOwners
        // has to be an owner to be able to set the guard
        GnosisSafe(payable(safeProxy)).setup(
            owners,
            1,
            address(0),
            new bytes(0),
            compatibilityFallbackHandler,
            address(0),
            0,
            payable(address(0))
        );

        console.log("PROTOCOL OWNER");
        DelegationOwner delegationOwner = DelegationOwner(delegationOwnerProxy);
        ProtocolOwner protocolOwner = ProtocolOwner(protocolOwnerProxy);
        //////////////////////////////////////////
        // Protocol Owner

        protocolOwner.initialize(protocolGuardBeacon, address(safeProxy), _owner, address(delegationOwner));

        console.log("DELEGATION OWNER");
        //////////////////////////////////////////
        // Delegation Owner

        delegationOwner.initialize(guardBeacon, address(safeProxy), _owner, _delegationController, protocolOwnerProxy);

        address delegationGuard = address(delegationOwner.guard());

        console.log("SET WALLET");
        //////////////////////////////////////////
        // Save wallet
        IDelegationWalletRegistry(registry).setWallet(
            safeProxy,
            _owner,
            delegationOwnerProxy,
            delegationGuard,
            protocolOwnerProxy
        );

        emit WalletDeployed(safeProxy, _owner, delegationOwnerProxy, delegationGuard, msg.sender);

        return (safeProxy, delegationOwnerProxy, delegationGuard, protocolOwnerProxy);
    }
}
