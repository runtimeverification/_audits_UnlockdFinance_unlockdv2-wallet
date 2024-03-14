// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { DelegationOwner, ProtocolOwner, DelegationWalletFactory, GuardOwner, DelegationOwner, TestNft, TestNftPlatform, Config, Errors } from "./utils/Config.sol";
import { Adapter } from "./mocks/Adapter.sol";

import { IGnosisSafe } from "../src/interfaces/IGnosisSafe.sol";
import { AssetLogic } from "../src/libs/logic/AssetLogic.sol";

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { GuardManager, GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { console } from "forge-std/console.sol";

contract UpgradeableBeaconTest is Config {
    event ExecutionSuccess(bytes32 txHash, uint256 payment);

    uint256 private safeProxyNftId;
    uint256 private kakarotoNftId;
    address[] assets;
    uint256[] assetIds;
    TestNft public testNft2;
    Adapter private adapter;

    function setUp() public {
        vm.startPrank(makeAddr("kiki"));
        (safeProxy, delegationOwnerProxy, protocolOwnerProxy, guardOwnerProxy) = delegationWalletFactory.deploy(
            delegationController
        );

        safe = GnosisSafe(payable(safeProxy));
        protocolOwner = ProtocolOwner(protocolOwnerProxy);
        delegationOwner = DelegationOwner(delegationOwnerProxy);

        vm.stopPrank();
    }

    function test_check_owner_beacon_proxy() public {
        // hoax(makeAddr("kiki"));
        // address _newProtocolOwnerImpl = address(new ProtocolOwner(address(makeAddr("lololo")), address(aclManager)));
        // assertEq(UpgradeableBeacon(protocolOwnerBeacon), address(0));
        // vm.startPrank(kakaroto);
        // // console.log("Beacon OWNER", UpgradeableBeacon(protocolOwnerBeacon).owner());
        // UpgradeableBeacon(protocolOwnerBeacon).upgradeTo(_newProtocolOwnerImpl);
        // vm.stopPrank();
        // assertEq(UpgradeableBeacon(protocolOwnerBeacon), address(0));
    }
}
