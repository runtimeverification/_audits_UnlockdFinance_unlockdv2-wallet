// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import { DelegationOwner, DelegationGuard, DelegationWalletFactory, TestNft, TestNftPlatform, Config } from "./utils/Config.sol";

import { IGnosisSafe } from "../src/interfaces/IGnosisSafe.sol";

import { GS } from "../src/test/GS.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { GuardManager, GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract DelegationOwnerTest is Config {
    event ExecutionSuccess(bytes32 txHash, uint256 payment);
    uint256 private safeProxyNftId;
    uint256 private kakarotoNftId;
    address[] assets;
    uint256[] assetIds;
    TestNft public testNft2;

    function setUp() public {
        // debugGs = new GS();

        vm.prank(kakaroto);
        (safeProxy, delegationOwnerProxy, delegationGuardProxy) = delegationWalletFactory.deploy(delegationController);

        safe = GnosisSafe(payable(safeProxy));
        delegationOwner = DelegationOwner(delegationOwnerProxy);
        delegationGuard = DelegationGuard(delegationGuardProxy);

        safeProxyNftId = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );
        kakarotoNftId = testNft.mint(kakaroto, "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/2");

        assets.push(address(testNft));
        assetIds.push(safeProxyNftId);

        testNft2 = new TestNft();
    }

    function test_delegate_only_rental_controller(
        address _nft,
        uint256 _id,
        uint256 _duration
    ) public {
        vm.assume(_duration != 0);
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__onlyDelegationController.selector);

        delegationOwner.delegate(_nft, _id, karpincho, _duration);
    }

    function test_delegate_noGuard(
        address _nft,
        uint256 _id,
        uint256 _duration
    ) public {
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

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkGuardConfigured_noGuard.selector);

        delegationOwner.delegate(_nft, _id, karpincho, _duration);
    }

    function test_delegate_not_owned_nft(uint256 _duration) public {
        vm.assume(_duration != 0);
        vm.prank(delegationController);

        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetNotOwned.selector);

        delegationOwner.delegate(address(testNft), kakarotoNftId, karpincho, _duration);
    }

    function test_delegate_approved_nft(uint256 _duration) public {
        vm.assume(_duration != 0);
        vm.prank(kakaroto);

        bytes memory payload = abi.encodeWithSignature("approve(address,uint256)", kakaroto, safeProxyNftId);
        safe.execTransaction(
            address(testNft),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call)
        );

        vm.prank(delegationController);

        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetApproved.selector);

        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);
    }

    function test_delegate_currently_delegated(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);
        vm.prank(delegationController);

        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);

        vm.prank(delegationController);
        vm.warp(block.timestamp + _duration - 1);

        vm.expectRevert(DelegationOwner.DelegationOwner__delegate_currentlyDelegated.selector);

        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);
    }

    function test_delegate_invalid_delegatee(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);
        vm.prank(delegationController);

        vm.expectRevert(DelegationOwner.DelegationOwner__delegate_invalidDelegatee.selector);

        delegationOwner.delegate(address(testNft), safeProxyNftId, address(0), _duration);
    }

    function test_delegate_invalid_duration() public {
        vm.prank(delegationController);

        vm.expectRevert(DelegationOwner.DelegationOwner__delegate_invalidDuration.selector);

        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 0);
    }

    function test_delegate_invalidExpiry(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));

        vm.prank(delegationController);

        vm.expectRevert(DelegationOwner.DelegationOwner__delegate_invalidExpiry.selector);

        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration + 1);
    }

    function test_delegate_should_work(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);
        vm.prank(delegationController);

        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(
                DelegationGuard.setDelegationExpiry.selector,
                address(testNft),
                safeProxyNftId,
                block.timestamp + _duration
            )
        );
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);

        (address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + _duration);
    }

    function test_delegate_should_work_with_locked_asset_and_ending_before_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(delegationController);

        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(
                DelegationGuard.setDelegationExpiry.selector,
                address(testNft),
                safeProxyNftId,
                block.timestamp + _duration - 1
            )
        );
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration - 1);

        (address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + _duration - 1);
    }

    function test_delegate_should_work_with_locked_asset_and_ending_at_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(delegationController);

        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(
                DelegationGuard.setDelegationExpiry.selector,
                address(testNft),
                safeProxyNftId,
                block.timestamp + _duration
            )
        );
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);

        (address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + _duration);
    }

    // // TODO - end delegate

    // delegate signature
    function test_delegateSignature_onlyRentController() public {
        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__onlyDelegationController.selector);

        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);
    }

    function test_delegateSignature_noGuard() public {
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

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkGuardConfigured_noGuard.selector);

        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);
    }

    function test_delegateSignature_invalidArity() public {
        assets.push(address(testNft2));

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegateSignature_invalidArity.selector);
        delegationOwner.delegateSignature(assets, assetIds, vegeta, 10 days);
    }

    function test_delegateSignature_currentlyDelegated() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegateSignature_currentlyDelegated.selector);
        delegationOwner.delegateSignature(assets, assetIds, vegeta, 10 days);
    }

    function test_delegateSignature_invalidDelegatee() public {
        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegateSignature_invalidDelegatee.selector);

        delegationOwner.delegateSignature(assets, assetIds, address(0), 10 days);
    }

    function test_delegateSignature_invalidDuration() public {
        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegateSignature_invalidDuration.selector);

        delegationOwner.delegateSignature(assets, assetIds, karpincho, 0);
    }

    function test_delegateSignature_assetNotOwned() public {
        uint256 duration = 10 days;
        uint256[] memory notOwnedAssetIds = new uint256[](1);
        notOwnedAssetIds[0] = kakarotoNftId;

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetNotOwned.selector);

        delegationOwner.delegateSignature(assets, notOwnedAssetIds, karpincho, duration);
    }

    function test_delegateSignature_assetApproved() public {
        bytes memory payload = abi.encodeWithSignature("approve(address,uint256)", kakaroto, safeProxyNftId);
        safe.execTransaction(
            address(testNft),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call)
        );

        vm.prank(delegationController);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetApproved.selector);

        uint256 duration = 10 days;
        delegationOwner.delegateSignature(assets, assetIds, karpincho, duration);
    }

    function test_delegateSignature_should_work_() public {
        uint256 duration = 10 days;
        vm.prank(delegationController);
        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(
                DelegationGuard.setDelegationExpiries.selector,
                assets,
                assetIds,
                block.timestamp + duration
            )
        );
        delegationOwner.delegateSignature(assets, assetIds, karpincho, duration);

        (address delegatee, uint256 from, uint256 to) = delegationOwner.signatureDelegation();

        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + duration);
    }

    // // TODO - end delegate signature

    // isValidSignature
    function test_isValidSignature_with_off_chain_signature_should_work() public {
        uint256 duration = 30 days;
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, duration);

        vm.warp(block.timestamp + 10);

        bytes32 singData = bytes32("hello world");
        bytes memory userSignature = getSignature(singData, karpinchoKey);

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(delegationOwner)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(userSignature.length),
            userSignature
        );

        assertEq(IGnosisSafe(address(safe)).isValidSignature(ECDSA.toEthSignedMessageHash(singData), signature), UPDATED_MAGIC_VALUE);
    }

    function test_isValidSignature_notDelegated() public {
        bytes memory singData = abi.encodePacked(bytes32("hello world"));
        bytes memory userSignature = getSignature(singData, vegetaKey);

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(delegationOwner)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(userSignature.length),
            userSignature
        );

        vm.expectRevert(DelegationOwner.DelegationOwner__isValidSignature_notDelegated.selector);
        IGnosisSafe(address(safe)).isValidSignature(singData, signature);
    }

    function test_isValidSignature_invalidSigner() public {
        uint256 duration = 30 days;

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, duration);

        vm.warp(block.timestamp + 10);

        bytes memory singData = abi.encodePacked(bytes32("hello world"));
        bytes memory userSignature = getSignature(singData, vegetaKey);

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(delegationOwner)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(userSignature.length),
            userSignature
        );

        vm.expectRevert(DelegationOwner.DelegationOwner__isValidSignature_invalidSigner.selector);
        IGnosisSafe(address(safe)).isValidSignature(singData, signature);
    }

    // execTransaction
    function test_execTransaction_notDelegated() public {
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__execTransaction_notDelegated.selector);

        delegationOwner.execTransaction(
            address(testNft),
            safeProxyNftId,
            address(testNftPlatform),
            0,
            abi.encodeWithSelector(TestNftPlatform.allowedFunction.selector),
            0,
            0,
            0,
            address(0),
            payable(0)
        );
    }

    function test_execTransaction_invalidDelegatee() public {
        uint256 duration = 30 days;
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, duration);

        vm.warp(block.timestamp + 10);

        vm.prank(vegeta);
        vm.expectRevert(DelegationOwner.DelegationOwner__execTransaction_invalidDelegatee.selector);

        delegationOwner.execTransaction(
            address(testNft),
            safeProxyNftId,
            address(testNftPlatform),
            0,
            abi.encodeWithSelector(TestNftPlatform.allowedFunction.selector),
            0,
            0,
            0,
            address(0),
            payable(0)
        );
    }

    function test_execTransaction_notAllowedFunction() public {
        uint256 duration = 30 days;
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, duration);

        vm.warp(block.timestamp + 10);

        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__execTransaction_notAllowedFunction.selector);

        delegationOwner.execTransaction(
            address(testNft),
            safeProxyNftId,
            address(testNftPlatform),
            0,
            abi.encodeWithSelector(TestNftPlatform.notAllowedFunction.selector),
            0,
            0,
            0,
            address(0),
            payable(0)
        );
    }

    function test_execTransaction_should_work() public {
        uint256 duration = 30 days;
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, duration);

        vm.warp(block.timestamp + 10);

        uint256 countBefore = testNftPlatform.count();

        vm.prank(karpincho);

        bool success = delegationOwner.execTransaction(
            address(testNft),
            safeProxyNftId,
            address(testNftPlatform),
            0,
            abi.encodeWithSelector(TestNftPlatform.allowedFunction.selector),
            0,
            0,
            0,
            address(0),
            payable(0)
        );

        assertEq(success, true);
        assertEq(testNftPlatform.count(), countBefore + 1);
    }

    // loan

    function test_lockAsset_onlyLoanController() public {
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__onlyLockController.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);
    }

    function test_lockAsset_noGuard() public {
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

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkGuardConfigured_noGuard.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);
    }

    function test_lockAsset_not_owned_nft(uint256 _duration) public {
        vm.assume(_duration > 0 && _duration < 100 * 365 days);
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetNotOwned.selector);

        delegationOwner.lockAsset(address(testNft), kakarotoNftId, block.timestamp + _duration);
    }

    function test_lockAsset_approved_nft(uint256 _duration) public {
        vm.assume(_duration > 0 && _duration < 100 * 365 days);
        vm.prank(kakaroto);

        bytes memory payload = abi.encodeWithSignature("approve(address,uint256)", kakaroto, safeProxyNftId);
        safe.execTransaction(
            address(testNft),
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            getTransactionSignature(kakarotoKey, address(testNft), payload, Enum.Operation.Call)
        );

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__checkOwnedAndNotApproved_assetApproved.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);
    }

    function test_lockAsset_assetLocked(uint256 _duration) public {
        vm.assume(_duration > 0 && _duration < 100 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.warp(_duration - 1);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__lockAsset_assetLocked.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);
    }

    function test_lockAsset_invalidClaimDate() public {
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__lockAsset_invalidClaimDate.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, 0);
    }

    function test_lockAsset_assetDelegatedLonger(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__lockAsset_assetDelegatedLonger.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration - 1);
    }

    function test_lockAsset_signatureDelegatedLonger(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, _duration);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__lockAsset_signatureDelegatedLonger.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration - 1);
    }

    function test_lockAsset_should_work() public {
        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));
    }

    function test_lockAsset_should_work_with_asset_delegated_shorter(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration);

        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration + 1);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));
    }

    function test_lockAsset_should_work_with_signature_delegated_shorter(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, _duration);

        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration + 1);

        assertTrue(delegationGuard.isLocked(address(testNft), safeProxyNftId));
    }

    function test_isAssetLocked_should_work() public {
        assertFalse(delegationOwner.isAssetLocked(address(testNft), safeProxyNftId));
        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);
        assertTrue(delegationOwner.isAssetLocked(address(testNft), safeProxyNftId));
    }

    function test_unlockAsset_onlyLoanController() public {
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__onlyLockController.selector);

        delegationOwner.unlockAsset(address(testNft), 1);
    }

    function test_unlockAsset_not_owned_nft() public {
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__unlockAsset_assetNotOwned.selector);

        delegationOwner.unlockAsset(address(testNft), kakarotoNftId);
    }

    function test_unlockAsset_should_work() public {
        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + 10 days);

        assertTrue(delegationGuard.isLocked(address(testNft), 1));

        vm.prank(nftfi);

        delegationOwner.unlockAsset(address(testNft), 1);

        assertFalse(delegationGuard.isLocked(address(testNft), 1));
    }

    function test_claimAsset_onlyLoanController(address _nft, uint256 _id) public {
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__onlyLockController.selector);

        delegationOwner.claimAsset(_nft, _id, address(this));
    }

    function test_claimAsset_not_owned_nft() public {
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);

        delegationOwner.claimAsset(address(testNft), kakarotoNftId, address(this));
    }

    function test_claimAsset_assetNotClaimable_not_locked() public {
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);

        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_assetNotClaimable_not_claimDate() public {
        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + 10 days);

        vm.warp(block.timestamp + 9 days);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_should_work() public {
        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + 10 days);

        assertEq(testNft.ownerOf(1), address(safeProxy));

        vm.warp(block.timestamp + 10 days);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));

        assertEq(testNft.ownerOf(1), address(this));
    }
}
