// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, Errors } from "src/DelegationOwner.sol";
import { DelegationGuard } from "src/DelegationGuard.sol";
import { DelegationWalletFactory } from "src/DelegationWalletFactory.sol";
import { DelegationRecipes } from "src/DelegationRecipes.sol";
import { DelegationWalletRegistry } from "src/DelegationWalletRegistry.sol";
import { AllowedControllers } from "src/AllowedControllers.sol";
import { TestNft } from "src/test/TestNft.sol";
import { TestNftPlatform } from "src/test/TestNftPlatform.sol";
import { IACLManager } from "src/interfaces/IACLManager.sol";
import { ICryptoPunks } from "../../src/interfaces/ICryptoPunks.sol";
import { ACLManager } from "../mocks/ACLManager.sol";
import { GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Config is Test {
    bytes32 public constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    uint256 public kakarotoKey = 2;
    address public kakaroto = vm.addr(kakarotoKey);

    uint256 public karpinchoKey = 3;
    address public karpincho = vm.addr(karpinchoKey);

    uint256 public vegetaKey = 4;
    address public vegeta = vm.addr(vegetaKey);

    uint256 public delegationControllerKey = 5;
    address public delegationController = vm.addr(delegationControllerKey);

    bytes4 public constant EIP1271_MAGIC_VALUE = 0x20c13b0b;
    bytes4 public constant UPDATED_MAGIC_VALUE = 0x1626ba7e;

    address public gnosisSafeTemplate = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552; // 4854169
    address public gnosisSafeProxyFactory = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2; // 4695402
    address public compatibilityFallbackHandler = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4; // 4854164
    uint256 public forkBlock = 17785165;
    TestNft public testNft;
    ICryptoPunks public testPunks;
    TestNftPlatform public testNftPlatform;
    TestNftPlatform public testPunksPlatform;

    IACLManager public aclManager;

    address public delegationOwnerImpl;
    address public delegationGuardImpl;
    address public ownerBeacon;
    address public guardBeacon;
    DelegationWalletFactory public delegationWalletFactory;
    DelegationRecipes public delegationRecipes;
    DelegationWalletRegistry public delegationWalletRegistry;
    AllowedControllers public allowedControllers;

    address public safeProxy;
    address public delegationOwnerProxy;
    address public delegationGuardProxy;

    GnosisSafe public safe;
    DelegationOwner public delegationOwner;
    DelegationGuard public delegationGuard;

    address[] public lockControllers;
    address[] public delegationControllers;

    address public constant REAL_OWNER = 0x052564eB0fd8b340803dF55dEf89c25C432f43f4;
    address public constant REAL_OWNER2 = 0x4d8E16A70F38414F33E8578913Eef6A0e4a633b5;

    uint256 public constant safeProxyPunkId = 407;
    uint256 public constant safeProxyPunkId2 = 409;

    constructor() {
        // Fork mainnet
        uint256 mainnetFork = vm.createFork("mainnet", forkBlock);
        vm.selectFork(mainnetFork);

        vm.startPrank(kakaroto);
        aclManager = new ACLManager(kakaroto);

        // Configure ADMINS

        aclManager.addProtocolAdmin(kakaroto);
        aclManager.addGovernanceAdmin(kakaroto);
        aclManager.addUpdaterAdmin(kakaroto);
        aclManager.addEmergencyAdmin(kakaroto);
        vm.stopPrank();
        testNft = new TestNft();
        testPunks = ICryptoPunks(0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB);
        testNftPlatform = new TestNftPlatform(address(testNft));
        testPunksPlatform = new TestNftPlatform(address(testPunks));

        delegationControllers.push(delegationController);

        delegationRecipes = new DelegationRecipes();
        allowedControllers = new AllowedControllers(delegationControllers);

        // DelegationOwner implementation
        delegationOwnerImpl = address(
            new DelegationOwner(
                address(testPunks),
                address(delegationRecipes),
                address(allowedControllers),
                address(aclManager)
            )
        );

        // DelegationGuard implementation
        delegationGuardImpl = address(new DelegationGuard(address(testPunks)));

        // deploy DelegationOwnerBeacon
        ownerBeacon = address(new UpgradeableBeacon(delegationOwnerImpl));

        // deploy DelegationGuardBeacon
        guardBeacon = address(new UpgradeableBeacon(delegationGuardImpl));

        delegationWalletRegistry = new DelegationWalletRegistry();
        delegationWalletFactory = new DelegationWalletFactory(
            gnosisSafeProxyFactory,
            gnosisSafeTemplate,
            compatibilityFallbackHandler,
            guardBeacon,
            ownerBeacon,
            address(delegationWalletRegistry)
        );
        delegationWalletRegistry.setFactory(address(delegationWalletFactory));
        vm.deal(kakaroto, 100 ether);
        vm.deal(karpincho, 100 ether);
        vm.deal(vegeta, 100 ether);

        address[] memory contracts = new address[](1);
        bytes4[] memory selectors = new bytes4[](1);
        string[] memory descriptions = new string[](1);

        contracts[0] = address(testNftPlatform);
        selectors[0] = TestNftPlatform.allowedFunction.selector;
        descriptions[0] = "TestNftPlatform - allowedFunction";
        delegationRecipes.add(address(testNft), contracts, selectors, descriptions);

        contracts[0] = address(testPunksPlatform);
        descriptions[0] = "TestPunksPlatform - allowedFunction";
        delegationRecipes.add(address(testPunks), contracts, selectors, descriptions);
    }

    function getSignature(bytes memory toSign, uint256 key) public pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 _s) = vm.sign(key, ECDSA.toEthSignedMessageHash(toSign));
        return abi.encodePacked(r, _s, v);
    }

    function getSignature(bytes32 toSign, uint256 key) public pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 _s) = vm.sign(key, ECDSA.toEthSignedMessageHash(toSign));
        return abi.encodePacked(r, _s, v);
    }

    function getTransactionSignature(
        uint256 key,
        address to,
        bytes memory data,
        Enum.Operation operation
    ) public view returns (bytes memory) {
        bytes32 toSign = GnosisSafe(payable(safeProxy)).getTransactionHash(
            to,
            0,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            payable(0),
            GnosisSafe(payable(safeProxy)).nonce()
        );

        (uint8 v, bytes32 r, bytes32 _s) = vm.sign(key, toSign);
        return abi.encodePacked(r, _s, v);
    }
}
