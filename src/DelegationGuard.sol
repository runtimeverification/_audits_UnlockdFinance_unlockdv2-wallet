// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC165 } from "@gnosis.pm/safe-contracts/contracts/interfaces/IERC165.sol";
import { Guard } from "@gnosis.pm/safe-contracts/contracts/base/GuardManager.sol";
import { OwnerManager, GuardManager } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { DelegationOwner } from "./DelegationOwner.sol";
import { ICryptoPunks } from "./interfaces/ICryptoPunks.sol";
import { IGnosisSafe } from "./interfaces/IGnosisSafe.sol";

/**
 * @title DelegationGuard
 * @author BootNode
 * @dev This contract protects a DelegationWallet.
 * - Prevents delegated o locked assets from being transferred.
 * - Prevents the approval of delegated or locked assets.
 * - Prevents all approveForAll.
 * - Prevents change in the configuration of the DelegationWallet.
 * - Prevents the remotion a this contract as the Guard of the DelegationWallet.
 */
contract DelegationGuard is Guard, Initializable {
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256)")));
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM_DATA =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256,bytes)")));

    address public immutable cryptoPunks;

    address internal delegationOwner;

    // any time an asset is locked or delegated, the address is saved here so any address present in this mapping
    // will be checked when a transfer is performed
    // nft address => true/false
    mapping(address => bool) internal checkAsset;

    // keccak256(address, nft id) => true/false
    mapping(bytes32 => bool) internal lockedAssets; // this locks assets until unlock

    // keccak256(address, nft id) => delegation expiry
    mapping(bytes32 => uint256) internal delegatedAssets; // this locks assets base on a date

    // ========== Custom Errors ===========
    error DelegationGuard__onlyDelegationOwner();
    error DelegationGuard__initialize_invalidDelegationOwner();
    error DelegationGuard__checkTransaction_noDelegateCall();
    error DelegationGuard__checkLocked_noTransfer();
    error DelegationGuard__checkLocked_noApproval();
    error DelegationGuard__checkApproveForAll_noApprovalForAll();
    error DelegationGuard__checkConfiguration_ownershipChangesNotAllowed();
    error DelegationGuard__checkConfiguration_guardChangeNotAllowed();
    error DelegationGuard__checkConfiguration_enableModuleNotAllowed();
    error DelegationGuard__checkConfiguration_setFallbackHandlerNotAllowed();

    /**
     * @notice This modifier indicates that only the DelegationOwner contract can execute a given function.
     */
    modifier onlyDelegationOwner() {
        if (delegationOwner != msg.sender) revert DelegationGuard__onlyDelegationOwner();
        _;
    }

    constructor(address _cryptoPunks) {
        cryptoPunks = _cryptoPunks;
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

    /**
     * @notice This function is called from Safe.execTransaction to perform checks before executing the transaction.
     */
    function checkTransaction(
        address _to,
        uint256,
        bytes calldata _data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address _msgSender
    ) external view override {
        // malicious owner can execute transactions to smart contracts by using Enum.Operation.DelegateCall in order to
        // manipulate the Safe's internal storage and even transfer locked NFTs out of the delegation wallet
        if (operation == Enum.Operation.DelegateCall) revert DelegationGuard__checkTransaction_noDelegateCall();

        // Transactions coming from DelegationOwner are already blocked/allowed there.
        // The delegatee calls execTransaction on DelegationOwner, it checks allowance then calls execTransaction
        // from Safe.
        if (_msgSender != delegationOwner && checkAsset[_to]) {
            _checkLocked(_to, _data);
        }

        // approveForAll should be never allowed since can't be checked before delegating or locking
        _checkApproveForAll(_data);

        _checkConfiguration(_to, _data);
    }

    /**
     * @notice This function is called from Safe.execTransaction to perform checks after executing the transaction.
     */
    function checkAfterExecution(bytes32 txHash, bool success) external view override {}

    /**
     * @notice Sets the delegation expiry for a group of assets.
     * @param _assets - The assets addresses.
     * @param _ids - The assets ids.
     * @param _expiry - The delegation expiry.
     */
    function setDelegationExpiries(
        address[] calldata _assets,
        uint256[] calldata _ids,
        uint256 _expiry
    ) external onlyDelegationOwner {
        uint256 length = _assets.length;
        for (uint256 j; j < length; ) {
            checkAsset[_assets[j]] = true;
            delegatedAssets[_assetId(_assets[j], _ids[j])] = _expiry;
            unchecked {
                ++j;
            }
        }
    }

    /**
     * @notice Sets the delegation expiry for an assets.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     * @param _expiry - The delegation expiry.
     */
    function setDelegationExpiry(address _asset, uint256 _id, uint256 _expiry) external onlyDelegationOwner {
        checkAsset[_asset] = true;
        delegatedAssets[_assetId(_asset, _id)] = _expiry;
    }

    /**
     * @notice Sets an asset as locked.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     */
    function lockAsset(address _asset, uint256 _id) external onlyDelegationOwner {
        if (!_isLocked(_asset, _id)) {
            checkAsset[_asset] = true;
            lockedAssets[_assetId(_asset, _id)] = true;
        }
    }

    /**
     * @notice Sets an asset as unlocked.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     */
    function unlockAsset(address _asset, uint256 _id) external onlyDelegationOwner {
        if (_isLocked(_asset, _id)) {
            lockedAssets[_assetId(_asset, _id)] = false;
        }
    }

    /**
     * @notice Returns if an asset is locked.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function isLocked(address _asset, uint256 _id) external view returns (bool) {
        return _isLocked(_asset, _id);
    }

    /**
     * @notice Returns asset delegation expiry.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function getExpiry(address _asset, uint256 _id) external view returns (uint256) {
        return delegatedAssets[_assetId(_asset, _id)];
    }

    /**
     * @notice This function prevents the execution of some functions when the destination contract is a locked or
     * delegated asset.
     * @param _to - Destination address of Safe transaction.
     * @param _data - Data payload of Safe transaction.
     */
    function _checkLocked(address _to, bytes calldata _data) internal view {
        bytes4 selector = _getSelector(_data);
        if (_to == cryptoPunks) {
            if (selector == ICryptoPunks.transferPunk.selector) {
                (, uint256 assetId) = abi.decode(_data[4:], (address, uint256));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noTransfer();
            } else if (selector == ICryptoPunks.offerPunkForSale.selector) {
                (uint256 assetId, ) = abi.decode(_data[4:], (uint256, uint256));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noApproval();
            } else if (selector == ICryptoPunks.offerPunkForSaleToAddress.selector) {
                (uint256 assetId, , ) = abi.decode(_data[4:], (uint256, uint256, address));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noApproval();
            } else if (selector == ICryptoPunks.acceptBidForPunk.selector) {
                (uint256 assetId, ) = abi.decode(_data[4:], (uint256, uint256));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noTransfer();
            }
        } else {
            // move this check to an adaptor per asset address?
            if (_isTransfer(selector)) {
                (, , uint256 assetId) = abi.decode(_data[4:], (address, address, uint256));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noTransfer();
            } else if (selector == IERC721.approve.selector) {
                (, uint256 assetId) = abi.decode(_data[4:], (address, uint256));
                if (_isDelegating(_to, assetId) || _isLocked(_to, assetId))
                    revert DelegationGuard__checkLocked_noApproval();
            }
        }
    }

    /**
     * @notice This function prevents the execution of the IERC721 setApprovalForAll function.
     * @param _data - Data payload of Safe transaction.
     */
    function _checkApproveForAll(bytes calldata _data) internal pure {
        bytes4 selector = _getSelector(_data);

        if (selector == IERC721.setApprovalForAll.selector)
            revert DelegationGuard__checkApproveForAll_noApprovalForAll();
    }

    /**
     * @notice This function prevents changes in the configuration of the Safe.
     * @param _to - Destination address of Safe transaction.
     * @param _data - Data payload of Safe transaction.
     */
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

            // Guard change not allowed
            if (selector == GuardManager.setGuard.selector)
                revert DelegationGuard__checkConfiguration_guardChangeNotAllowed();

            // Adding modules is not allowed
            if (selector == IGnosisSafe.enableModule.selector)
                revert DelegationGuard__checkConfiguration_enableModuleNotAllowed();

            // Changing FallbackHandler is not allowed
            if (selector == IGnosisSafe.setFallbackHandler.selector)
                revert DelegationGuard__checkConfiguration_setFallbackHandlerNotAllowed();
        }
    }

    /**
     * @notice Checks if an asset is delegated.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function _isDelegating(address _asset, uint256 _id) internal view returns (bool) {
        return (block.timestamp <= delegatedAssets[_assetId(_asset, _id)]);
    }

    /**
     * @notice Checks if an asset is locked.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function _isLocked(address _asset, uint256 _id) internal view returns (bool) {
        return lockedAssets[keccak256(abi.encodePacked(_asset, _id))];
    }

    /**
     * @notice Checks if `_selector` is one of the ERC721 possible transfers.
     * @param _selector - Function selector.
     */
    function _isTransfer(bytes4 _selector) internal pure returns (bool) {
        return (_selector == IERC721.transferFrom.selector ||
            _selector == ERC721_SAFE_TRANSFER_FROM ||
            _selector == ERC721_SAFE_TRANSFER_FROM_DATA);
    }

    /**
     * @notice Returns internal identification of an asset.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function _assetId(address _asset, uint256 _id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_asset, _id));
    }

    /**
     * @notice Returns selector of a data payload.
     * @param _data - Data payload of Safe transaction
     */
    function _getSelector(bytes calldata _data) internal pure returns (bytes4) {
        return bytes4(_data[:4]);
    }

    function supportsInterface(
        bytes4 _interfaceId
    )
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
