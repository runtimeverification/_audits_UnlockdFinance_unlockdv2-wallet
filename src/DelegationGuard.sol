// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

// TODO - use (but it is not in npm package but it is on Foundry lib)
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC165 } from "@gnosis.pm/safe-contracts/contracts/interfaces/IERC165.sol";
import { Guard } from "@gnosis.pm/safe-contracts/contracts/base/GuardManager.sol";
import { OwnerManager, GuardManager } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {DelegationOwner} from "./DelegationOwner.sol";

/**
 * @title DelegationGuard
 * @author BootNode
 * @dev This contract protects a DelegationWallet.
 * - Prevents delegated o locked assets from being transferred.
 * - Prevents the approval of delegated or locked assets.
 * - Prevents all approveForAll.
 * - Prevents change in the configuration of the DelegationWallet.
 * - Prevents the remotion a this contract as the Guard of the DelegationWallet on some scenarios.
 */
contract DelegationGuard is Guard, Initializable {
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256)")));
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM_DATA =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256,bytes)")));

    address internal delegationOwner;

    // any time an asset is locked or delegated, the address is saved here so any address present in this mapping
    // will be checked when a transfer is performed
    // nft address => true/false
    mapping(address => bool) internal checkAsset;

    // keccak256(address, nft id) => true/false
    mapping(bytes32 => bool) internal lockedAssets; // this locks assets until unlock
    uint256 public lockedCount;


    // keccak256(address, nft id) => delegation expiry
    mapping(bytes32 => uint256) internal delegatedAssets; // this locks assets base on a date

    // this saves the latest expiry in order to know if there is an locked by date asset on any given time
    uint256 public lastExpiry;

    // ========== Custom Errors ===========
    error DelegationGuard__onlyDelegationOwner();
    error DelegationGuard__initialize_invalidDelegationOwner();
    error DelegationGuard__checkLocked_noTransfer();
    error DelegationGuard__checkLocked_noApproval();
    error DelegationGuard__checkApproveForAll_noApprovalForAll();
    error DelegationGuard__checkConfiguration_ownershipChangesNotAllowed();
    error DelegationGuard__checkConfiguration_guardChangeNotAllowed();

    modifier onlyDelegationOwner() {
        if (delegationOwner != msg.sender) revert DelegationGuard__onlyDelegationOwner();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _delegationOwner) public initializer {
        if (_delegationOwner == address(0)) revert DelegationGuard__initialize_invalidDelegationOwner();
        delegationOwner = _delegationOwner;
    }

    // solhint-disable-next-line payable-fallback
    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    // do not allow the owner to do stuff on locked assets
    function checkTransaction(
        address _to,
        uint256,
        bytes calldata _data,
        Enum.Operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address _msgSender
    ) external view override {
        // transactions coming from DelegationOwner are already blocked/allowed there
        // delegatee calls execTransaction on DelegationOwner, it checks allowance then calls execTransaction from Safe

        // is one of the real owners
        if (_msgSender != delegationOwner && checkAsset[_to]) {
            _checkLocked(_to, _data);
        }

        // approveForAll should be never allowed since can't be checked before delegating or locking
        _checkApproveForAll(_data);

        _checkConfiguration(_to, _data);
    }

    function checkAfterExecution(bytes32 txHash, bool success) external view override {}

    function setDelegationExpiries(
        address[] calldata _assets,
        uint256[] calldata _assetIds,
        uint256 _expiry
    ) external onlyDelegationOwner {
        for (uint256 j; j < _assets.length; ) {
            checkAsset[_assets[j]] = true;
            delegatedAssets[_delegationId(_assets[j], _assetIds[j])] = _expiry;
            unchecked {
                ++j;
            }
        }

        // This function could be called, in order to end a delegation, using the current timestamp or 0 as
        // expiry. In that scenario it is not possible to update lastExpiry, since it is used in _checkConfiguration
        // function as a flag to check if there is any delegation in progress, it could end not allowing to change
        // the guard until lastExpiry with no real delegation in progress.
        if (_expiry > lastExpiry) {
            lastExpiry = _expiry;
        }
    }

    function setDelegationExpiry(
        address _asset,
        uint256 _assetId,
        uint256 _expiry
    ) external onlyDelegationOwner {
        checkAsset[_asset] = true;
        delegatedAssets[_delegationId(_asset, _assetId)] = _expiry;

        // This function could be called, in order to end a delegation, using the current timestamp or 0 as
        // expiry. In that scenario it is not possible to update lastExpiry, since it is used in _checkConfiguration
        // function as a flag to check if there is any delegation in progress, it could end not allowing to change
        // the guard until lastExpiry with no real delegation in progress.
        if (_expiry > lastExpiry) {
            lastExpiry = _expiry;
        }
    }

    function lockAsset(address _asset, uint256 _id) external onlyDelegationOwner {
        if (!_isLocked(_asset, _id)) {
            checkAsset[_asset] = true;
            lockedCount += 1;
            lockedAssets[keccak256(abi.encodePacked(_asset, _id))] = true;
        }
    }

    function unlockAsset(address _asset, uint256 _id) external onlyDelegationOwner {
        if (_isLocked(_asset, _id)) {
            lockedCount -= 1;
            lockedAssets[keccak256(abi.encodePacked(_asset, _id))] = false;
        }
    }

    function isLocked(address _asset, uint256 _assetId) external view returns (bool) {
        return _isLocked(_asset, _assetId);
    }

    function getExpiry(address _asset, uint256 _assetId) external view returns (uint256) {
        return delegatedAssets[_delegationId(_asset, _assetId)];
    }

    function _checkLocked(address _to, bytes calldata _data) internal view {
        bytes4 selector = _getSelector(_data);
        // move this check to an adaptor per asset address?
        if (_isTransfer(selector)) {
            (, , uint256 assetId) = abi.decode(_data[4:], (address, address, uint256));
            if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                revert DelegationGuard__checkLocked_noTransfer();
        }

        if (selector == IERC721.approve.selector) {
            (, uint256 assetId) = abi.decode(_data[4:], (address, uint256));
            if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                revert DelegationGuard__checkLocked_noApproval();
        }
    }

    function _checkApproveForAll(bytes calldata _data) internal pure {
        bytes4 selector = _getSelector(_data);
        if (selector == IERC721.setApprovalForAll.selector)
            revert DelegationGuard__checkApproveForAll_noApprovalForAll();
    }

    function _checkConfiguration(address _to, bytes calldata _data) internal view {
        bytes4 selector = _getSelector(_data);

        if (_to == DelegationOwner(delegationOwner).safe()) {
            // ownership change not allowed while this guard is configured
            if (
                selector == OwnerManager.addOwnerWithThreshold.selector ||
                selector == OwnerManager.removeOwner.selector ||
                selector == OwnerManager.swapOwner.selector ||
                selector == OwnerManager.changeThreshold.selector
            ) revert DelegationGuard__checkConfiguration_ownershipChangesNotAllowed();

            // Guard change not allowed while delegating or locked asset
            if (
                (lockedCount > 0 || block.timestamp < lastExpiry) &&
                selector == GuardManager.setGuard.selector
            ) revert DelegationGuard__checkConfiguration_guardChangeNotAllowed();
        }
    }

    function _isDelegating(address _asset, uint256 _assetId) internal view returns (bool) {
        return (block.timestamp <= delegatedAssets[_delegationId(_asset, _assetId)]);
    }

    function _isLocked(address _asset, uint256 _assetId) internal view returns (bool) {
        return lockedAssets[keccak256(abi.encodePacked(_asset, _assetId))];
    }

    function _isTransfer(bytes4 selector) internal pure returns (bool) {
        return (selector == IERC721.transferFrom.selector ||
            selector == ERC721_SAFE_TRANSFER_FROM ||
            selector == ERC721_SAFE_TRANSFER_FROM_DATA);
    }

    function _delegationId(address _asset, uint256 _assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_asset, _assetId));
    }

    function _getSelector(bytes memory _data) internal pure returns (bytes4 selector) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(_data, 32))
        }
    }

    function supportsInterface(bytes4 _interfaceId)
        external
        view
        virtual
        returns (
            // override
            bool
        )
    {
        return
            _interfaceId == type(Guard).interfaceId || // 0xe6d7a83a
            _interfaceId == type(IERC165).interfaceId; // 0x01ffc9a7
    }
}
