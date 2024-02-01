// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, ProtocolOwner, DelegationWalletFactory, GuardOwner, DelegationOwner, TestNft, TestNftPlatform, Config, Errors } from "./utils/Config.sol";
import { Adapter } from "./mocks/Adapter.sol";

import { IGnosisSafe } from "../src/interfaces/IGnosisSafe.sol";
import { AssetLogic } from "../src/libs/logic/AssetLogic.sol";

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { GuardManager, GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { console } from "forge-std/console.sol";

contract ProtocolOwnerTest is Config {
    event ExecutionSuccess(bytes32 txHash, uint256 payment);

    uint256 private safeProxyNftId;
    uint256 private kakarotoNftId;
    address[] assets;
    uint256[] assetIds;
    TestNft public testNft2;
    Adapter private adapter;

    function setUp() public {
        vm.startPrank(kakaroto);
        (safeProxy, delegationOwnerProxy, protocolOwnerProxy, guardOwnerProxy) = delegationWalletFactory.deploy(
            delegationController
        );

        safe = GnosisSafe(payable(safeProxy));
        protocolOwner = ProtocolOwner(protocolOwnerProxy);
        delegationOwner = DelegationOwner(delegationOwnerProxy);

        safeProxyNftId = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/1"
        );
        kakarotoNftId = testNft.mint(kakaroto, "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/2");

        assets.push(address(testNft));
        assetIds.push(safeProxyNftId);

        testNft2 = new TestNft();
        aclManager.addProtocolAdmin(kakaroto);
        allowedControllers.setDelegationControllerAllowance(karpincho, true);

        adapter = new Adapter(address(token));
        token.mint(address(adapter), 1000);
        vm.stopPrank();
    }

    function test_delegate_one_execution() public {
        vm.startPrank(kakaroto);
        protocolOwner.delegateOneExecution(address(kakaroto), true);
        assertTrue(protocolOwner.isDelegatedExecution(address(kakaroto)));
        vm.stopPrank();
    }

    function test_delegate_one_execution_non_protocol() public {
        vm.startPrank(karpincho);

        vm.expectRevert(Errors.Caller_notProtocol.selector);
        protocolOwner.delegateOneExecution(address(kakaroto), true);
        assertFalse(protocolOwner.isDelegatedExecution(address(kakaroto)));
        vm.stopPrank();
    }

    function test_delegate_one_execution_zero_protocol() public {
        vm.startPrank(kakaroto);

        vm.expectRevert(Errors.ProtocolOwner__invalidDelegatedAddressAddress.selector);
        protocolOwner.delegateOneExecution(address(0), true);
        assertFalse(protocolOwner.isDelegatedExecution(address(kakaroto)));
        vm.stopPrank();
    }

    function test_sell_approval_non_approved() public {
        vm.assume(testNft.balanceOf(address(safeProxy)) == 1);
        vm.assume(token.balanceOf(address(adapter)) == 1000);
        vm.assume(token.balanceOf(address(safeProxy)) == 0);

        vm.startPrank(kakaroto);

        // WE no approve the transfers
        vm.expectRevert(Errors.ProtocolOwner__invalidDelegatedAddressAddress.selector);
        protocolOwner.approveSale(address(testNft), safeProxyNftId, address(token), 1000, address(adapter), 0);
    }

    function test_sell_approval_wrong_loanId() public {
        vm.assume(testNft.balanceOf(address(safeProxy)) == 1);
        vm.assume(token.balanceOf(address(adapter)) == 1000);
        vm.assume(token.balanceOf(address(safeProxy)) == 0);

        vm.startPrank(kakaroto);

        protocolOwner.delegateOneExecution(address(kakaroto), true);
        vm.expectRevert(Errors.DelegationOwner__wrongLoanId.selector);
        protocolOwner.approveSale(
            address(testNft),
            safeProxyNftId,
            address(token),
            1000,
            address(adapter),
            bytes32(uint256(0x11))
        );
    }

    function test_sell_approval() public {
        vm.assume(testNft.balanceOf(address(safeProxy)) == 1);
        vm.assume(token.balanceOf(address(adapter)) == 1000);
        vm.assume(token.balanceOf(address(safeProxy)) == 0);

        vm.startPrank(kakaroto);

        // WE approve the transfers
        protocolOwner.delegateOneExecution(address(kakaroto), true);
        protocolOwner.approveSale(address(testNft), safeProxyNftId, address(token), 1000, address(adapter), 0);
        assertTrue(IERC721(address(testNft)).getApproved(safeProxyNftId) == address(adapter));
        assertTrue(IERC20(address(token)).allowance(address(safeProxy), kakaroto) == 1000);
    }

    function test_sell() public {
        vm.assume(testNft.balanceOf(address(safeProxy)) == 1);
        vm.assume(token.balanceOf(address(adapter)) == 1000);
        vm.assume(token.balanceOf(address(safeProxy)) == 0);

        vm.startPrank(kakaroto);

        // WE approve the transfers
        protocolOwner.delegateOneExecution(address(kakaroto), true);
        protocolOwner.approveSale(address(testNft), safeProxyNftId, address(token), 1000, address(adapter), 0);

        protocolOwner.delegateOneExecution(address(kakaroto), true);
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.sell(address(testNft), safeProxyNftId, address(safeProxy));

        bytes memory payload = abi.encodeWithSignature(
            "sell(address,uint256,address)",
            address(testNft),
            safeProxyNftId,
            address(safeProxy)
        );
        protocolOwner.execTransaction(address(adapter), 0, payload, 0, 0, 0, address(0), payable(0));

        assertEq(testNft.balanceOf(address(safeProxy)), 0);
        assertEq(testNft.balanceOf(address(adapter)), 1);

        assertEq(token.balanceOf(address(safeProxy)), 1000);
        vm.stopPrank();
    }

    function test_initialize_exceptions() public {
        vm.startPrank(kakaroto);

        vm.expectRevert("Initializable: contract is already initialized");
        protocolOwner.initialize(address(0), address(0), address(0), address(0));

        address _protocolOwnerBeacon = address(new UpgradeableBeacon(protocolOwnerImpl));
        address _protocolOwnerProxy = address(new BeaconProxy(_protocolOwnerBeacon, new bytes(0)));

        vm.expectRevert(Errors.DelegationGuard__initialize_invalidGuardBeacon.selector);
        ProtocolOwner(_protocolOwnerProxy).initialize(address(0), address(0), address(0), address(0));

        address guard = address(GuardOwner(guardOwnerProxy).guard());

        vm.expectRevert(Errors.DelegationGuard__initialize_invalidSafe.selector);
        ProtocolOwner(_protocolOwnerProxy).initialize(guard, address(0), address(0), address(0));

        vm.expectRevert(Errors.DelegationGuard__initialize_invalidOwner.selector);
        ProtocolOwner(_protocolOwnerProxy).initialize(guard, address(safeProxy), address(0), address(0));

        vm.stopPrank();
    }

    function test_changeOwner() public {
        vm.startPrank(kakaroto);
        protocolOwner.changeOwner(address(testNft), safeProxyNftId, address(kakaroto));
        assertEq(testNft.ownerOf(safeProxyNftId), kakaroto);
        vm.stopPrank();
    }

    function test_changeOwner_not_protocol() public {
        vm.startPrank(karpincho);
        vm.expectRevert(Errors.Caller_notProtocol.selector);
        protocolOwner.changeOwner(address(testNft), safeProxyNftId, address(kakaroto));
        assertEq(testNft.ownerOf(safeProxyNftId), address(safe));
        vm.stopPrank();
    }

    function test_batch_setLoanId() public {
        uint256 safeProxyNftId_two = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/3"
        );

        vm.startPrank(kakaroto);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = delegationOwner.assetId(address(testNft), safeProxyNftId);
        ids[1] = delegationOwner.assetId(address(testNft), safeProxyNftId_two);

        protocolOwner.batchSetLoanId(ids, keccak256(abi.encode(100)));
        for (uint i = 0; i <= ids.length - 1; i++) {
            assertTrue(protocolOwner.getLoanId(ids[i]) == keccak256(abi.encode(100)));
        }

        protocolOwner.batchSetToZeroLoanId(ids);
        for (uint i = 0; i <= ids.length - 1; i++) {
            assertTrue(protocolOwner.getLoanId(ids[i]) == 0);
        }
        vm.stopPrank();
    }

    function test_safeSetLoanId() public {
        uint256 safeProxyNftId_two = testNft.mint(
            address(safeProxy),
            "ipfs://bafybeihpjhkeuiq3k6nqa3fkgeigeri7iebtrsuyuey5y6vy36n345xmbi/3"
        );
        vm.startPrank(address(safeProxy));
        testNft.approve(makeAddr("dummy"), safeProxyNftId_two);
        assertEq(testNft.getApproved(safeProxyNftId_two), makeAddr("dummy"));
        vm.stopPrank();
        vm.startPrank(kakaroto);

        protocolOwner.safeSetLoanId(address(testNft), safeProxyNftId_two, keccak256(abi.encode(100)));

        assertTrue(
            protocolOwner.getLoanId(delegationOwner.assetId(address(testNft), safeProxyNftId_two)) ==
                keccak256(abi.encode(100))
        );
        assertEq(testNft.getApproved(safeProxyNftId_two), address(0));
        vm.stopPrank();
    }

    function test_batch_setLoanId_already_done() public {
        vm.startPrank(kakaroto);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = delegationOwner.assetId(address(testNft), safeProxyNftId);

        protocolOwner.batchSetLoanId(ids, keccak256(abi.encode(100)));
        vm.expectRevert(Errors.DelegationOwner__assetAlreadyLocked.selector);
        protocolOwner.batchSetLoanId(ids, keccak256(abi.encode(100)));

        protocolOwner.batchSetToZeroLoanId(ids);
        vm.expectRevert(Errors.DelegationOwner__assetNotLocked.selector);
        protocolOwner.batchSetToZeroLoanId(ids);

        vm.stopPrank();
    }
}
