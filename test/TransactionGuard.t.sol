// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, DelegationWalletFactory, ProtocolOwner, GuardOwner, TestNft, TransactionGuard, TestNftPlatform, Config, Errors } from "./utils/Config.sol";
import { Adapter } from "./mocks/Adapter.sol";

import { IGnosisSafe } from "../src/interfaces/IGnosisSafe.sol";
import { AssetLogic } from "../src/libs/logic/AssetLogic.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { GuardManager, GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IERC721Extended, IERC721 } from "../src/interfaces/IERC721Extended.sol";

contract TransactionGuardTest is Config {
    event ExecutionSuccess(bytes32 txHash, uint256 payment);
    uint256 private safeProxyNftId;
    uint256 private safeProxyNftId2;
    uint256 private tokenId;
    address[] assets;
    uint256[] assetIds;
    TestNft public testNft2;
    Adapter private adapter;

    function setUp() public {
        vm.startPrank(kakaroto);
        testNft2 = new TestNft();

        allowedControllers.setDelegationControllerAllowance(karpincho, true);

        adapter = new Adapter(address(token));
        token.mint(address(adapter), 1000);
        vm.stopPrank();

        vm.startPrank(kiki);
        (safeProxy, delegationOwnerProxy, protocolOwnerProxy, guardOwnerProxy) = delegationWalletFactory.deploy(
            delegationController
        );

        safe = GnosisSafe(payable(safeProxy));
        delegationOwner = DelegationOwner(delegationOwnerProxy);
        protocolOwner = ProtocolOwner(protocolOwnerProxy);

        tokenId = testNft.mint(kiki, "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/2");

        safeProxyNftId = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );

        safeProxyNftId2 = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );
        assets.push(address(testNft));
        assetIds.push(safeProxyNftId);

        vm.stopPrank();
    }

    function test_execTransaction_transfer() public {
        vm.prank(makeAddr("kiki"));
        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kiki,
            safeProxyNftId
        );
        assertEq(IERC721(testNft).ownerOf(safeProxyNftId), address(safeProxy));
        bytes memory tSig = getTransactionSignature(kikiKey, address(testNft), payload, Enum.Operation.Call);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        assertEq(IERC721(testNft).ownerOf(safeProxyNftId), address(kiki));
        vm.stopPrank();
    }

    function test_execTransaction_transfer_lockedAsset() public {
        vm.startPrank(kakaroto);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = delegationOwner.assetId(address(testNft), safeProxyNftId);
        ids[1] = delegationOwner.assetId(address(testNft), safeProxyNftId2);

        protocolOwner.batchSetLoanId(ids, keccak256(abi.encode(100)));
        vm.stopPrank();
        vm.prank(kiki);

        bytes memory payload = abi.encodeWithSelector(
            IERC721.transferFrom.selector,
            address(safeProxy),
            kiki,
            safeProxyNftId
        );
        assertEq(IERC721(testNft).ownerOf(safeProxyNftId), address(safeProxy));
        bytes memory tSig = getTransactionSignature(kikiKey, address(testNft), payload, Enum.Operation.Call);
        vm.expectRevert(Errors.TransactionGuard__checkLocked_noTransfer.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        vm.stopPrank();
    }

    function test_execTransaction_burn() public {
        vm.prank(makeAddr("kiki"));
        bytes memory payload = abi.encodeWithSelector(IERC721Extended.burn.selector, safeProxyNftId);
        assertEq(IERC721(testNft).ownerOf(safeProxyNftId), address(safeProxy));
        bytes memory tSig = getTransactionSignature(kikiKey, address(testNft), payload, Enum.Operation.Call);

        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        vm.expectRevert("ERC721: invalid token ID");
        IERC721(testNft).ownerOf(safeProxyNftId);
        vm.stopPrank();
    }

    function test_execTransaction_burn_lockedAsset() public {
        vm.startPrank(kakaroto);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = delegationOwner.assetId(address(testNft), safeProxyNftId);
        ids[1] = delegationOwner.assetId(address(testNft), safeProxyNftId2);

        protocolOwner.batchSetLoanId(ids, keccak256(abi.encode(100)));
        vm.stopPrank();
        vm.prank(kiki);

        bytes memory payload = abi.encodeWithSelector(IERC721Extended.burn.selector, safeProxyNftId);
        assertEq(IERC721(testNft).ownerOf(safeProxyNftId), address(safeProxy));
        bytes memory tSig = getTransactionSignature(kikiKey, address(testNft), payload, Enum.Operation.Call);
        vm.expectRevert(Errors.TransactionGuard__checkLocked_noBurn.selector);
        safe.execTransaction(address(testNft), 0, payload, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), tSig);

        vm.stopPrank();
    }
}
