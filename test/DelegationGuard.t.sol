// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

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
        (safeProxy, delegationOwnerProxy, delegationGuardProxy) = delegationWalletFactory.deploy(delegationController, nftfi);

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

    function test_setDelegationExpiries_should_update_lastExpiry_whit_a_greater() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiries(assets, assetIds, expiry);

        assertEq(delegationGuard.lastExpiry(), expiry);

        assets2.push(address(1));
        assets2.push(address(1));
        assetIds2.push(1);
        assetIds2.push(2);

        uint256 expiry2 = expiry + 2;

        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiries(assets2, assetIds2, expiry2);

        assertEq(delegationGuard.lastExpiry(), expiry2);
    }

    function test_setDelegationExpiries_should_not_update_lastExpiry_whit_a_lower() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiries(assets, assetIds, expiry);

        assertEq(delegationGuard.lastExpiry(), expiry);

        assets2.push(address(1));
        assets2.push(address(1));
        assetIds2.push(1);
        assetIds2.push(2);

        uint256 expiry2 = expiry - 2;

        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiries(assets2, assetIds2, expiry2);

        assertEq(delegationGuard.lastExpiry(), expiry);
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

    function test_setDelegationExpiry_should_update_lastExpiry_whit_a_greater() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        assertEq(delegationGuard.lastExpiry(), expiry);

        uint256 expiry2 = expiry + 2;

        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(1), 1, expiry2);

        assertEq(delegationGuard.lastExpiry(), expiry2);
    }

    function test_setDelegationExpiry_should_not_update_lastExpiry_whit_a_lower() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        assertEq(delegationGuard.lastExpiry(), expiry);

        uint256 expiry2 = expiry - 2;

        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(1), 1, expiry2);

        assertEq(delegationGuard.lastExpiry(), expiry);
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
        assertEq(delegationGuard.lockedCount(), 1);
    }

    function test_lockAsset_locking_twice_should_not_update_count() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        assertEq(delegationGuard.lockedCount(), 1);

        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        assertEq(delegationGuard.lockedCount(), 1);
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
        assertEq(delegationGuard.lockedCount(), 1);

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        assertFalse(delegationGuard.isLocked(address(testNft), safeProxyNftId));
        assertEq(delegationGuard.lockedCount(), 0);
    }

    function test_unlockAsset_unlocking_twice_should_not_update_count() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.lockAsset(address(testNft), safeProxyNftId);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));
        assertEq(delegationGuard.lockedCount(), 1);

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        assertEq(delegationGuard.lockedCount(), 0);

        vm.prank(delegationOwnerProxy);
        delegationGuard.unlockAsset(address(testNft), safeProxyNftId);

        assertEq(delegationGuard.lockedCount(), 0);
    }


    // _checkLocked
    function test_owner_can_no_transfer_out_delegated_asset() public {
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

    function test_owner_can_change_guard_after_delegation_expires() public {
        vm.prank(delegationOwnerProxy);
        delegationGuard.setDelegationExpiry(address(testNft), safeProxyNftId, expiry);

        vm.warp(block.timestamp + 10 days + 1);

        bytes memory payload = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bytes memory tSig = getTransactionSignature(kakarotoKey, address(safeProxy), payload, Enum.Operation.Call);

        vm.prank(kakaroto);
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

    function test_nft_owner_can_change_guard_after_an_asset_is_unlocked() public {
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

    // TODO - test ownership changes not allowed with guard

    // TODO - test approveForAll not allowed with guard
}
