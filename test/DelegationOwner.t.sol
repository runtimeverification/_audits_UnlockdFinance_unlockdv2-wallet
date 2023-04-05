// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
        kakarotoNftId = testNft.mint(kakaroto, "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/2");

        assets.push(address(testNft));
        assetIds.push(safeProxyNftId);

        testNft2 = new TestNft();

        allowedControllers.setLockControllerAllowance(karpincho, true);
        allowedControllers.setDelegationControllerAllowance(karpincho, true);
    }

    function test_setDelegationController_onlyOwner() public {
        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__onlyOwner.selector);
        delegationOwner.setDelegationController(karpincho, true);
    }

    function test_setDelegationController_should_work() public {
        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, true);

        assertTrue(delegationOwner.delegationControllers(karpincho));
    }

    function test_setDelegationController_should_allow_to_unset_a_controller() public {
        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, true);
        assertTrue(delegationOwner.delegationControllers(karpincho));

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, false);
        assertFalse(delegationOwner.delegationControllers(karpincho));
    }

    function test_setDelegationController_notAllowedController() public {
        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__setDelegationController_notAllowedController.selector);
        delegationOwner.setDelegationController(vegeta, true);
    }

    function test_setDelegationController_should_allow_to_unset_non_allowed_controller() public {
        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, true);

        allowedControllers.setDelegationControllerAllowance(karpincho, false);

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, false);
    }

    function test_setLockController_onlyOwner() public {
        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__onlyOwner.selector);
        delegationOwner.setLockController(karpincho, true);
    }

    function test_setLockController_should_work() public {
        vm.prank(kakaroto);
        delegationOwner.setLockController(karpincho, true);

        assertTrue(delegationOwner.lockControllers(karpincho));
    }

    function test_setLockController_should_allow_to_unset_a_controller() public {
        vm.prank(kakaroto);
        delegationOwner.setLockController(karpincho, true);
        assertTrue(delegationOwner.lockControllers(karpincho));

        vm.prank(kakaroto);
        delegationOwner.setLockController(karpincho, false);
        assertFalse(delegationOwner.lockControllers(karpincho));
    }

    function test_setLockController_notAllowedController() public {
        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__setLockController_notAllowedController.selector);
        delegationOwner.setLockController(vegeta, true);
    }

    function test_setLockController_should_allow_to_unset_non_allowed_controller() public {
        vm.prank(kakaroto);
        delegationOwner.setLockController(karpincho, true);

        allowedControllers.setLockControllerAllowance(karpincho, false);

        vm.prank(kakaroto);
        delegationOwner.setLockController(karpincho, false);
    }

    function test_delegate_only_rental_controller(address _nft, uint256 _id, uint256 _duration) public {
        vm.assume(_duration != 0);
        vm.prank(karpincho);

        vm.expectRevert(DelegationOwner.DelegationOwner__onlyDelegationController.selector);

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

        (address controller, address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(controller, delegationController);
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

        (address controller, address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(controller, delegationController);
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

        (address controller, address delegatee, uint256 from, uint256 to) = delegationOwner.delegations(
            delegationOwner.assetId(address(testNft), safeProxyNftId)
        );

        assertEq(controller, delegationController);
        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + _duration);
    }

    // end delegate
    function test_endDelegate_notDelegated() public {
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_notDelegated.selector);
        delegationOwner.endDelegate(address(testNft), safeProxyNftId);
    }

    function test_endDelegate_onlyDelegationCreator() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_onlyDelegationCreator.selector);
        delegationOwner.endDelegate(address(testNft), safeProxyNftId);
    }

    function test_endDelegate_should_not_allow_new_delegationController_to_end_delegation_not_created() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, true);

        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_onlyDelegationCreator.selector);
        delegationOwner.endDelegate(address(testNft), safeProxyNftId);
    }

    function test_endDelegate_should_work() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        vm.prank(delegationController);
        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(DelegationGuard.setDelegationExpiry.selector, address(testNft), safeProxyNftId, 0)
        );
        delegationOwner.endDelegate(address(testNft), safeProxyNftId);

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_endDelegate_should_allow_old_delegationController_to_end_delegation_created() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(delegationController, false);

        vm.prank(delegationController);
        delegationOwner.endDelegate(address(testNft), safeProxyNftId);

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    // delegate signature
    function test_delegateSignature_onlyRentController() public {
        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__onlyDelegationController.selector);

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

        (address controller, address delegatee, uint256 from, uint256 to) = delegationOwner.signatureDelegation();

        assertEq(controller, delegationController);
        assertEq(delegatee, karpincho);
        assertEq(from, block.timestamp);
        assertEq(to, block.timestamp + duration);
    }

    // end delegate signature
    function test_endDelegateSignature_notDelegated() public {
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_notDelegated.selector);
        delegationOwner.endDelegateSignature();
    }

    function test_endDelegateSignature_onlyDelegationCreator() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_onlyDelegationCreator.selector);
        delegationOwner.endDelegateSignature();
    }

    function test_endDelegateSignature_should_not_allow_new_delegationController_to_end_delegation_not_created()
        public
    {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(karpincho, true);

        vm.prank(karpincho);
        vm.expectRevert(DelegationOwner.DelegationOwner__delegationCreatorChecks_onlyDelegationCreator.selector);
        delegationOwner.endDelegateSignature();
    }

    function test_endDelegateSignature_should_work() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.prank(delegationController);
        vm.expectCall(
            address(delegationGuard),
            abi.encodeWithSelector(DelegationGuard.setDelegationExpiries.selector, assets, assetIds, 0)
        );
        delegationOwner.endDelegateSignature();

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_endDelegateSignature_should_allow_old_delegationController_to_end_delegation_created() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.prank(kakaroto);
        delegationOwner.setDelegationController(delegationController, false);

        vm.prank(delegationController);
        delegationOwner.endDelegateSignature();

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

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

        assertEq(
            IGnosisSafe(address(safe)).isValidSignature(ECDSA.toEthSignedMessageHash(singData), signature),
            UPDATED_MAGIC_VALUE
        );
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

    function test_lockAsset_assetLocked() public {
        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockAsset_assetLocked.selector);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 20 days);
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

        vm.expectRevert(DelegationOwner.DelegationOwner__checkClaimDate_assetDelegatedLonger.selector);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration - 1);
    }

    function test_lockAsset_signatureDelegatedLonger(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 100 * 365 days);

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, _duration);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__checkClaimDate_signatureDelegatedLonger.selector);

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

    // change claimDate
    function test_change_ClaimDate_DelegationOwner__lockCreatorChecks_assetNotLocked(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_assetNotLocked.selector);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, block.timestamp + _duration);
    }

    function test_change_ClaimDate_onlyLockCreator(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_onlyLockCreator.selector);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, block.timestamp + deleDuration - 1);
    }

    function test_change_ClaimDate_assetDelegatedLonger(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, deleDuration);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkClaimDate_assetDelegatedLonger.selector);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, block.timestamp + deleDuration - 1);
    }

    function test_change_ClaimDate_signatureDelegatedLonger(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, deleDuration);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__checkClaimDate_signatureDelegatedLonger.selector);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, block.timestamp + deleDuration - 1);
    }

    function test_change_ClaimDate_should_work_extending_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 newClaimDate = delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)) +
            1;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_reducing_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 newClaimDate = delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)) -
            1;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_reducing_claimDate_to_current_timestamp(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 newClaimDate = block.timestamp;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_delegation_shorter_than_new_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, deleDuration);

        uint256 newClaimDate = block.timestamp + deleDuration + 1;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_delegation_equal_than_new_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, deleDuration);

        uint256 newClaimDate = block.timestamp + deleDuration;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_sig_delegation_shorter_than_new_claimDate(
        uint256 _duration
    ) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, deleDuration);

        uint256 newClaimDate = block.timestamp + deleDuration + 1;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_sig_delegation_equal_than_new_claimDate(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 deleDuration = _duration - 5 days;

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, deleDuration);

        uint256 newClaimDate = block.timestamp + deleDuration;

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_change_ClaimDate_should_work_with_lock_creator_after_changing_lockController(
        uint256 _duration
    ) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        uint256 newClaimDate = delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)) +
            1;

        vm.prank(kakaroto);
        delegationOwner.setLockController(nftfi, false);

        vm.prank(nftfi);
        delegationOwner.changeClaimDate(address(testNft), safeProxyNftId, newClaimDate);

        assertEq(delegationOwner.lockedAssets(delegationOwner.assetId(address(testNft), safeProxyNftId)), newClaimDate);
    }

    function test_unlockAsset_assetNotLocked(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_assetNotLocked.selector);
        delegationOwner.unlockAsset(address(testNft), safeProxyNftId);
    }

    function test_unlockAsset_onlyLockCreator(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_onlyLockCreator.selector);
        delegationOwner.unlockAsset(address(testNft), safeProxyNftId);
    }

    function test_unlockAsset_not_owned_nft() public {
        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_assetNotLocked.selector);

        delegationOwner.unlockAsset(address(testNft), kakarotoNftId);
    }

    function test_unlockAsset_should_work() public {
        vm.prank(nftfi);

        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);

        assertTrue(delegationGuard.isLocked(address(testNft), 1));

        vm.prank(nftfi);

        delegationOwner.unlockAsset(address(testNft), safeProxyNftId);

        assertFalse(delegationGuard.isLocked(address(testNft), 1));
    }

    function test_unlockAsset_should_work_with_lock_creator_after_changing_lockController(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(kakaroto);
        delegationOwner.setLockController(nftfi, false);

        vm.prank(nftfi);
        delegationOwner.unlockAsset(address(testNft), safeProxyNftId);

        assertFalse(delegationGuard.isLocked(address(testNft), 1));
    }

    function test_claimAsset_assetNotLocked(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_assetNotLocked.selector);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, karpincho);
    }

    function test_claimAsset_onlyLockCreator(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(kakaroto);
        vm.expectRevert(DelegationOwner.DelegationOwner__lockCreatorChecks_onlyLockCreator.selector);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, karpincho);
    }

    function test_claimAsset_assetNotClaimable_asset_delegated_before_expiry(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration - 1);

        vm.warp(block.timestamp + _duration - 2);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_assetNotClaimable_asset_delegated_at_expiry(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration - 1);

        vm.warp(block.timestamp + _duration - 1);

        vm.prank(nftfi);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_assetNotClaimable_asset_included_in_signature_before_expiry(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + _duration);
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, _duration - 1);

        vm.warp(block.timestamp + _duration - 2);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_assetNotClaimable_asset_included_in_signature_at_expiry(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + _duration);
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, _duration - 1);

        vm.warp(block.timestamp + _duration - 1);

        vm.expectRevert(DelegationOwner.DelegationOwner__claimAsset_assetNotClaimable.selector);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));
    }

    function test_claimAsset_should_work_after_claim_data(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + _duration);

        assertEq(testNft.ownerOf(1), address(safeProxy));

        vm.warp(block.timestamp + _duration);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));

        assertEq(testNft.ownerOf(1), address(this));
    }

    function test_claimAsset_should_work_before_claim_data_no_delegation(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), 1, block.timestamp + _duration);

        assertEq(testNft.ownerOf(1), address(safeProxy));

        vm.warp(block.timestamp + _duration - 1);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));

        assertEq(testNft.ownerOf(1), address(this));
    }

    function test_claimAsset_should_work_when_asset_delegated_expired(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, _duration - 2);

        vm.warp(block.timestamp + _duration - 1);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));

        assertEq(testNft.ownerOf(1), address(this));
    }

    function test_claimAsset_should_work_with_lock_creator_after_changing_lockController(uint256 _duration) public {
        vm.assume(_duration > 10 days && _duration < 10 * 365 days);

        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + _duration);

        vm.prank(kakaroto);
        delegationOwner.setLockController(nftfi, false);

        vm.prank(nftfi);
        delegationOwner.claimAsset(address(testNft), safeProxyNftId, address(this));

        assertEq(testNft.ownerOf(1), address(this));
    }

    // utils

    function test_isAssetLocked_should_work() public {
        assertFalse(delegationOwner.isAssetLocked(address(testNft), safeProxyNftId));
        vm.prank(nftfi);
        delegationOwner.lockAsset(address(testNft), safeProxyNftId, block.timestamp + 10 days);
        assertTrue(delegationOwner.isAssetLocked(address(testNft), safeProxyNftId));
    }

    function test_isSignatureDelegated_should_work() public {
        assertFalse(delegationOwner.isSignatureDelegated());

        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        assertTrue(delegationOwner.isSignatureDelegated());
    }

    function test_isSignatureDelegated_should_work_until_delegation_expires() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.warp(block.timestamp + 10 days);

        assertTrue(delegationOwner.isSignatureDelegated());

        vm.warp(block.timestamp + 1);

        assertFalse(delegationOwner.isSignatureDelegated());
    }

    function test_isAssetDelegated_should_work_when_asset_is_not_delegated_at_all() public {
        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_isAssetDelegated_should_work_when_asset_is_delegated() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        assertTrue(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_isAssetDelegated_should_work_until_delegation_expires() public {
        vm.prank(delegationController);
        delegationOwner.delegate(address(testNft), safeProxyNftId, karpincho, 10 days);

        vm.warp(block.timestamp + 10 days);

        assertTrue(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));

        vm.warp(block.timestamp + 1);

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_isAssetDelegated_should_work_when_asset_is_included_in_signature_delegated() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        assertTrue(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }

    function test_isAssetDelegated_should_work_until_signature_delegation_expires() public {
        vm.prank(delegationController);
        delegationOwner.delegateSignature(assets, assetIds, karpincho, 10 days);

        vm.warp(block.timestamp + 10 days);

        assertTrue(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));

        vm.warp(block.timestamp + 1);

        assertFalse(delegationOwner.isAssetDelegated(address(testNft), safeProxyNftId));
    }
}
