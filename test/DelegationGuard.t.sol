// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, DelegationGuard, DelegationWalletFactory, TestNft, TestNftPlatform, Config } from "./utils/Config.sol";

import { IGnosisSafe } from "../src/interfaces/IGnosisSafe.sol";

import { GS } from "../src/test/GS.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { OwnerManager, GuardManager, GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";

contract DelegationGuardTest is Config {
    uint256 private safeProxyNftId;
    uint256 private safeProxyNftId2;
    address[] assets;
    address[] assets2;
    uint256[] assetIds;
    uint256[] assetIds2;
    uint256 expiry;

    function setUp() public {
        // debugGs = new GS();
        // testNft = new TestNft();
        // testNftPlatform = new TestNftPlatform(address(testNft));

        vm.prank(kakaroto);
        (safeProxy, delegationOwnerProxy, delegationGuardProxy) = delegationWalletFactory.deploy(
            delegationController,
            nftfi
        );

        safe = GnosisSafe(payable(safeProxy));
        delegationOwner = DelegationOwner(delegationOwnerProxy);
        delegationGuard = DelegationGuard(delegationGuardProxy);

        safeProxyNftId = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );

        safeProxyNftId2 = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );

        assets.push(address(testNft));
        assets.push(address(testNft));
        assetIds.push(safeProxyNftId);
        assetIds.push(safeProxyNftId2);

        expiry = block.timestamp + 10 days;
    }

    //setDelegationExpiries
    function test_setDelegationExpiries_onlyDelegationOwner() public {
        vm.expectRevert(DelegationGuard.DelegationGuard__onlyDelegationOwner.selector);
        delegationGuard.setDelegationExpiries(assets, assetIds, expiry);
    }

    function test_setDelegationExpiries_should_work() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiries(assets, assetIds, expiry);

        assertEq(delegationGuard.getExpiry(address(testNft), safeProxyNftId), expiry);
        assertEq(delegationGuard.getExpiry(address(testNft), safeProxyNftId2), expiry);
    }

    //setDelegationExpiry
    function test_setDelegationExpiry_onlyDelegationOwner() public {
        vm.expectRevert(DelegationGuard.DelegationGuard__onlyDelegationOwner.selector);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);
    }

    function test_setDelegationExpiry_should_work() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        assertEq(delegationGuard.getExpiry(address(testNft), safeProxyNftId), expiry);
    }

    //lockAsset
    function test_lockAsset_onlyDelegationOwner() public {
        vm.expectRevert(DelegationGuard.DelegationGuard__onlyDelegationOwner.selector);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);
    }

    function test_lockAsset_should_work() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));
    }

    //unlockAsset
    function test_unlockAsset_onlyDelegationOwner() public {
        vm.expectRevert(DelegationGuard.DelegationGuard__onlyDelegationOwner.selector);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);
    }

    function test_unlockAsset_should_work() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        assertFalse(delegationGuard.isLocked(address(testNft), safeProxyNftId));
    }

    // _checkLocked
    function test_owner_can_not_execute_a_delegatecall_operation() public {
        bytes memory storageAtBefore = safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1);
        address configuredGuardBefore = abi.decode(storageAtBefore, (address));

        vm.startPrank(kakaroto);

        GuardManipulator guardMan = new GuardManipulator();

        bytes memory payload = abi.encodeWithSelector(
            GuardManipulator.manipulateGuard.selector,
            address(0) // https://github.com/safe-global/safe-contracts/blob/6b3784f10a7262d3b857139914aaa33082990435/contracts/Safe.sol#L148
        );

        bytes memory tSig = getTransactionSignature(
            kakarotoKey,
            address(guardMan),
            payload,
            Enum.Operation.DelegateCall
        );

        vm.expectRevert(DelegationGuard.DelegationGuard__checkTransaction_noDelegateCall.selector);
        safe.execTransaction(
            address(guardMan),
            0,
            payload,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );

        bytes memory storageAtAfter = safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1);
        address configuredGuardAfter = abi.decode(storageAtAfter, (address));

        assertEq(configuredGuardAfter, configuredGuardBefore);
    }

    function test_owner_can_not_transfer_out_delegated_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 1);

        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kakaroto,
            safeProxyNftId
        );

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noTransfer.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.ownerOf(1), address(safeProxy));
    }

    function test_owner_can_transfer_out_delegated_asset_after_expiry() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 10 days + 1);

        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kakaroto,
            safeProxyNftId
        );

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.ownerOf(1), kakaroto);
    }

    function test_owner_can_not_approve_delegated_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 1);

        bytes memory payload = abi.encodeWithSelector(IERC721.approve.selector, kakaroto, safeProxyNftId);

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noApproval.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.getApproved(safeProxyNftId), address(0));
    }

    function test_owner_can_approve_delegated_asset_after_expiry() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 10 days + 1);

        bytes memory payload = abi.encodeWithSelector(IERC721.approve.selector, kakaroto, safeProxyNftId);

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.getApproved(safeProxyNftId), kakaroto);
    }

    function test_owner_can_no_transfer_out_locked_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kakaroto,
            safeProxyNftId
        );

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noTransfer.selector);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.ownerOf(1), address(safeProxy));
    }

    function test_owner_can_transfer_out_unlocked_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kakaroto,
            safeProxyNftId
        );

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noTransfer.selector);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.ownerOf(1), address(safeProxy));

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.ownerOf(1), kakaroto);
    }

    function test_owner_can_not_approve_locked_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(IERC721.approve.selector, kakaroto, safeProxyNftId);

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noApproval.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.getApproved(safeProxyNftId), address(0));
    }

    function test_owner_can_approve_unlocked_asset() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(IERC721.approve.selector, kakaroto, safeProxyNftId);

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkLocked_noApproval.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.getApproved(safeProxyNftId), address(address(0)));

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(testNft.getApproved(safeProxyNftId), kakaroto);
    }

    // _checkConfiguration - guard
    function test_owner_can_no_change_guard_while_delegating() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 1);

        bytes memory payload = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_guardChangeNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    function test_owner_can_no_change_guard_after_delegation_expires() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 10 days + 1);

        bytes memory payload = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_guardChangeNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    function test_nft_owner_can_no_change_guard_while_an_asset_is_locked() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_guardChangeNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    function test_nft_owner_can_not_change_guard_after_an_asset_is_unlocked() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        bytes memory payload = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_guardChangeNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_guardChangeNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    // _checkConfiguration - addOwnerWithThreshold
    function test_nft_owner_can_not_addOwnerWithThreshold_when_guard_is_configured() public {
        bytes memory payload = abi.encodeWithSelector(OwnerManager.addOwnerWithThreshold.selector, vegeta, 2);
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_ownershipChangesNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    // _checkConfiguration - removeOwner
    function test_nft_owner_can_not_removeOwner_when_guard_is_configured() public {
        bytes memory payload = abi.encodeWithSelector(
            OwnerManager.removeOwner.selector,
            kakaroto,
            address(delegationOwner),
            0
        );
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_ownershipChangesNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    // _checkConfiguration - swapOwner
    function test_nft_owner_can_not_swapOwner_when_guard_is_configured() public {
        bytes memory payload = abi.encodeWithSelector(
            OwnerManager.swapOwner.selector,
            kakaroto,
            address(delegationOwner),
            vegeta
        );
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_ownershipChangesNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    // _checkConfiguration - changeThreshold
    function test_nft_owner_can_not_changeThreshold_when_guard_is_configured() public {
        bytes memory payload = abi.encodeWithSelector(OwnerManager.changeThreshold.selector, 2);
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_ownershipChangesNotAllowed.selector);
        safe.execTransaction(
            address(safeProxy),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            tSig
        );
    }

    // _checkConfiguration - enableModule
    function test_owner_can_not_enable_a_module() public {
        vm.startPrank(kakaroto);

        bytes memory payload = abi.encodeWithSelector(IGnosisSafe.enableModule.selector, address(kakaroto));

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safe), payload, Enum.Operation.Call);

        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_enableModuleNotAllowed.selector);
        safe.execTransaction(address(safe), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertFalse(safe.isModuleEnabled(kakaroto));
    }

    // _checkConfiguration - enableModule
    function test_owner_can_not_set_new_fallback_handler() public {
        bytes32 FALLBACK_HANDLER_STORAGE_SLOT = 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
        bytes memory storageAtBefore = safe.getStorageAt(uint256(FALLBACK_HANDLER_STORAGE_SLOT), 1);
        address fallBackHandlerBefore = abi.decode(storageAtBefore, (address));

        vm.startPrank(kakaroto);

        bytes memory payload = abi.encodeWithSelector(IGnosisSafe.setFallbackHandler.selector, address(testPunks));

        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safe), payload, Enum.Operation.Call);

        vm.expectRevert(DelegationGuard.DelegationGuard__checkConfiguration_setFallbackHandlerNotAllowed.selector);
        safe.execTransaction(address(safe), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        bytes memory storageAtAfter = safe.getStorageAt(uint256(FALLBACK_HANDLER_STORAGE_SLOT), 1);
        address fallBackHandlerAfter = abi.decode(storageAtAfter, (address));

        assertEq(fallBackHandlerAfter, fallBackHandlerBefore);
    }

    // _checkApproveForAll
    function test_nft_owner_can_not_call_approveForAll__when_guard_is_configured() public {
        bytes memory payload = abi.encodeWithSelector(IERC721.setApprovalForAll.selector, kakaroto, true);
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationGuard.DelegationGuard__checkApproveForAll_noApprovalForAll.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);
    }
}

contract GuardManipulator {
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    function manipulateGuard(address guard) external {
        bytes32 slot = GUARD_STORAGE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, guard)
        }
    }
}
