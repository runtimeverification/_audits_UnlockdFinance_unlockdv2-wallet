// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { IGnosisSafe } from "./interfaces/IGnosisSafe.sol";
import { DelegationGuard } from "./DelegationGuard.sol";
import { DelegationRecipes } from "./DelegationRecipes.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ISignatureValidator } from "@gnosis.pm/safe-contracts/contracts/interfaces/ISignatureValidator.sol";
import { GnosisSafe } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";

// import "forge-std/console2.sol";

/**
 * @title DelegationOwner
 * @author BootNode
 * @dev This contract contains the logic that enables asset/signature delegates to interact with a Gnosis Safe wallet.
 * In the case of assets delegates, it will allow them to execute functions though the Safe, only those registered
 * as allowed on the DelegationRecipes contract.
 * In the case of signatures it validates that a signature was made by the current delegatee.
 * It is also used by the delegation controller to set delegations and the lock controller to lock, unlock and claim
 * assets.
 *
 * It should be use a proxy's implementation.
 */
contract DelegationOwner is ISignatureValidator, Initializable {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    bytes32 public constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /**
     * @notice Delegation information, it is used for assets and signatures.
     *
     * @param delegatee - The delegatee address.
     * @param from - The date (seconds timestamp) when the delegation starts.
     * @param to - The date (seconds timestamp) when the delegation ends.
     */
    struct Delegation {
        address delegatee;
        uint256 from;
        uint256 to;
    }

    /**
     * @notice Safe wallet address.
     */
    address public safe;
    /**
     * @notice The owner of the DelegationWallet - TODO do we need this.
     */
    address public owner;

    // TODO - Add delegationController setter
    //      - Should we have multiple delegation controllers?
    //      - Who can set a new delegation controller? The wallet owner?
    /**
     * @notice The delegation controller address. Allowed to execute delegation related functions.
     */
    address public delegationController;

    // TODO - Add lockController setter
    //      - Should we have multiple lock controllers?
    //      - Who can set a new lock controller? The wallet owner?
    //      - If multiple lock controllers, we need to know which one locked an asset, only that should be able to unlock or claim
    /**
     * @notice The lock controller address. Allowed to execute asset locking related functions.
     */
    address public lockController;
    /**
     * @notice The DelegationGuard address.
     */
    DelegationGuard public guard;
    /**
     * @notice The DelegationRecipes address.
     */
    DelegationRecipes public recipes;

    bool internal isExecuting;
    bytes32 internal currentTxHash;

    /**
     * @notice Stores the list of asset delegations. keccak256(address, nft id) => Delegation
     */
    mapping(bytes32 => Delegation) public delegations;

    /**
     * @notice Stores the current signature delegation.
     */
    Delegation public signatureDelegation;

    /**
     * @notice List of assets affected by last signatureDelegation
     */
    mapping(uint256 => EnumerableSet.Bytes32Set) private signatureDelegationAssets;
    uint256 private currentSignatureDelegationAssets;

    /**
     * @notice Stores for each locked assets the date since it turns claimable. keccak256(address, nft id) => claimDate
     */
    mapping(bytes32 => uint256) public lockedAssets;


    // ========== Events ===========
    event NewDelegation(
        address indexed asset,
        uint256 indexed assetId,
        uint256 from,
        uint256 to,
        address indexed delegatee
    );
    event EndDelegation(address indexed asset,uint256 indexed assetId);
    event DelegatedSignature(uint256 from, uint256 to, address indexed delegatee, address[] assets, uint256[] assetIds);
    event EndDelegatedSignature(address[] assets, uint256[] assetIds);
    event LockedAsset(address indexed asset, uint256 indexed assetId);
    event UnlockedAsset(address indexed asset, uint256 indexed assetId);
    event ClaimedAsset(address indexed asset, uint256 indexed assetId, address indexed receiver);
    event TransferredAsset(address indexed asset, uint256 indexed assetId, address indexed receiver);

    // ========== Custom Errors ===========
    error DelegationGuard__initialize_invalidGuardBeacon();
    error DelegationGuard__initialize_invalidRecipes();
    error DelegationGuard__initialize_invalidSafe();
    error DelegationGuard__initialize_invalidOwner();

    error DelegationOwner__onlyDelegationController();
    error DelegationOwner__onlyLockController();

    error DelegationOwner__delegate_currentlyDelegated();
    error DelegationOwner__delegate_invalidDelegatee();
    error DelegationOwner__delegate_invalidDuration();
    error DelegationOwner__delegate_invalidExpiry();
    error DelegationOwner__endDelegate_notDelegated();

    error DelegationOwner__delegateSignature_invalidExpiry(address asset, uint256 id);
    error DelegationOwner__delegateSignature_invalidArity();
    error DelegationOwner__delegateSignature_currentlyDelegated();
    error DelegationOwner__delegateSignature_invalidDelegatee();
    error DelegationOwner__delegateSignature_invalidDuration();
    error DelegationOwner__endDelegateSignature_invalidArity();
    error DelegationOwner__endDelegateSignature_notDelegated();

    error DelegationOwner__isValidSignature_notDelegated();
    error DelegationOwner__isValidSignature_invalidSigner();
    error DelegationOwner__isValidSignature_invalidExecSig();

    error DelegationOwner__execTransaction_notDelegated();
    error DelegationOwner__execTransaction_invalidDelegatee();
    error DelegationOwner__execTransaction_notAllowedFunction();
    error DelegationOwner__execTransaction_notSuccess();

    error DelegationOwner__lockAsset_invalidClaimDate();
    error DelegationOwner__lockAsset_assetLocked();
    error DelegationOwner__lockAsset_assetDelegatedLonger();
    error DelegationOwner__lockAsset_signatureDelegatedLonger();
    error DelegationOwner__unlockAsset_assetNotOwned();

    error DelegationOwner__transferAsset_assetNotOwned();

    error DelegationOwner__claimAsset_assetNotClaimable();
    error DelegationOwner__claimAsset_notSuccess();

    error DelegationOwner__checkGuardConfigured_noGuard();

    error DelegationOwner__checkOwnedAndNotApproved_assetNotOwned();
    error DelegationOwner__checkOwnedAndNotApproved_assetApproved();

    /**
     * @notice This modifier indicates that only the Delegation Controller can execute a given function.
     */
    modifier onlyDelegationController() {
        if (address(delegationController) != msg.sender) revert DelegationOwner__onlyDelegationController();
        _;
    }

    /**
     * @notice This modifier indicates that only the Lock Controller can execute a given function.
     */
    modifier onlyLockController() {
        if (lockController != msg.sender) revert DelegationOwner__onlyLockController();
        _;
    }

    /**
     * @dev Disables the initializer in order to prevent implementation initialization.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the proxy state.
     * @param _guardBeacon - The address of the beacon where the proxy gets the implementation address.
     * @param _recipes - The DelegationRecipes address.
     * @param _safe - The DelegationWallet address, the GnosisSafe.
     * @param _owner - The owner of the DelegationWallet.
     * @param _delegationController - The address that acts as the delegation controller.
     * @param _lockController - The address that acts as the lock controller.
     */
    function initialize(
        address _guardBeacon,
        address _recipes,
        address _safe,
        address _owner,
        address _delegationController,
        address _lockController
    ) public initializer {
        if (_guardBeacon == address(0)) revert DelegationGuard__initialize_invalidGuardBeacon();
        if (_recipes == address(0)) revert DelegationGuard__initialize_invalidRecipes();
        if (_safe == address(0)) revert DelegationGuard__initialize_invalidSafe();
        if (_owner == address(0)) revert DelegationGuard__initialize_invalidOwner();

        safe = _safe;
        owner = _owner;
        delegationController = _delegationController;
        lockController = _lockController;
        recipes = DelegationRecipes(_recipes);

        address guardProxy = address(
            new BeaconProxy(_guardBeacon, abi.encodeWithSelector(DelegationGuard.initialize.selector, address(this)))
        );
        guard = DelegationGuard(guardProxy);

        _setupGuard(_safe, guard);
    }

    /**
     * @notice Delegates the usage of an asset to the `_delegatee` for a `_duration` of time.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     * @param _delegatee - The delegatee address.
     * @param _duration - The duration of the delegation expressed in seconds.
     */
    function delegate(
        address _asset,
        uint256 _id,
        address _delegatee,
        uint256 _duration
    ) external onlyDelegationController {
        _checkGuardConfigured();
        _checkOwnedAndNotApproved(_asset, _id);

        bytes32 id = assetId(_asset, _id);
        Delegation storage delegation = delegations[id];

        if (_isDelegating(delegation)) revert DelegationOwner__delegate_currentlyDelegated();
        if (_delegatee == address(0)) revert DelegationOwner__delegate_invalidDelegatee();
        if (_duration == 0) revert DelegationOwner__delegate_invalidDuration();

        delegation.delegatee = _delegatee;
        uint256 from = block.timestamp;
        uint256 to = block.timestamp + _duration;
        delegation.from = from;
        delegation.to = to;

        uint256 claimDate = lockedAssets[id];
        if (claimDate > 0 && claimDate < to) revert DelegationOwner__delegate_invalidExpiry();

        emit NewDelegation(_asset, _id, from, to, _delegatee);

        guard.setDelegationExpiry(_asset, _id, to);
    }

    /**
     * @notice Ends asset usage delegation.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     */
    function endDelegate(
        address _asset,
        uint256 _id
    ) external onlyDelegationController {
        _checkGuardConfigured();

        Delegation storage delegation = delegations[assetId(_asset, _id)];

        if (!_isDelegating(delegation)) revert DelegationOwner__endDelegate_notDelegated();

        delegation.to = block.timestamp;

        emit EndDelegation(_asset, _id);

        guard.setDelegationExpiry(_asset, _id, block.timestamp);
    }

    /**
     * @notice Delegates the usage of the signature to the `_delegatee` for a `_duration` of time. Locking a group of
     * assets in the wallet.
     * @param _assets - The asset addresses.
     * @param _ids - The asset ids.
     * @param _delegatee - The delegatee address.
     * @param _duration - The duration of the delegation expressed in seconds.
     */
    function delegateSignature(
        address[] calldata _assets,
        uint256[] calldata _ids,
        address _delegatee,
        uint256 _duration
    ) external onlyDelegationController {
        _checkGuardConfigured();

        if (_assets.length != _ids.length) revert DelegationOwner__delegateSignature_invalidArity();
        if (_isDelegating(signatureDelegation)) revert DelegationOwner__delegateSignature_currentlyDelegated();
        if (_delegatee == address(0)) revert DelegationOwner__delegateSignature_invalidDelegatee();
        if (_duration == 0) revert DelegationOwner__delegateSignature_invalidDuration();

        uint256 delegationExpiry = block.timestamp + _duration;

        currentSignatureDelegationAssets += 1;

        for (uint256 j; j < _assets.length; ) {
            _checkOwnedAndNotApproved(_assets[j], _ids[j]);

            bytes32 id = assetId(_assets[j], _ids[j]);
            uint256 claimDate = lockedAssets[id];
            if (claimDate > 0 && claimDate < delegationExpiry) revert DelegationOwner__delegateSignature_invalidExpiry(_assets[j], _ids[j]);

            signatureDelegationAssets[currentSignatureDelegationAssets].add(id);

            unchecked {
                ++j;
            }
        }

        Delegation memory newDelegation = Delegation(_delegatee, block.timestamp, delegationExpiry);

        signatureDelegation = newDelegation;

        emit DelegatedSignature(newDelegation.from, newDelegation.to, _delegatee, _assets, _ids);

        guard.setDelegationExpiries(_assets, _ids, delegationExpiry);
    }

    /**
     * @notice Ends the delegation of the usage of the signature to the `_delegatee`. Unlocking a group of assets.
     * @param _assets - The asset addresses.
     * @param _ids - The asset ids.
     */
    function endDelegateSignature(
        address[] calldata _assets,
        uint256[] calldata _ids
    ) external onlyDelegationController {
        _checkGuardConfigured();

        if (_assets.length != _ids.length) revert DelegationOwner__endDelegateSignature_invalidArity();
        if (!_isDelegating(signatureDelegation)) revert DelegationOwner__endDelegateSignature_notDelegated();

        signatureDelegation.to = block.timestamp;

        emit EndDelegatedSignature(_assets, _ids);

        guard.setDelegationExpiries(_assets, _ids, block.timestamp);
    }

    /**
     * @notice Execute a transaction through the GnosisSafe wallet.
     * The sender should be the delegatee of the given asset and the function should be allowed for the collection.
     */
    function execTransaction(
        address _asset,
        uint256 _id,
        address _to,
        uint256 _value,
        bytes calldata _data,
        uint256 _safeTxGas,
        uint256 _baseGas,
        uint256 _gasPrice,
        address _gasToken,
        address payable _refundReceiver
    ) external returns (bool success) {
        Delegation storage delegation = delegations[assetId(_asset, _id)];

        if (!_isDelegating(delegation)) revert DelegationOwner__execTransaction_notDelegated();
        if (delegation.delegatee != msg.sender) revert DelegationOwner__execTransaction_invalidDelegatee();
        if (!isAllowedFunction(_asset, _to, _getSelector(_data)))
            revert DelegationOwner__execTransaction_notAllowedFunction();

        isExecuting = true;
        currentTxHash = IGnosisSafe(payable(safe)).getTransactionHash(
            // Transaction info
            _to,
            _value,
            _data,
            Enum.Operation.Call,
            _safeTxGas,
            // Payment info
            _baseGas,
            _gasPrice,
            _gasToken,
            _refundReceiver,
            // Signature info
            IGnosisSafe(payable(safe)).nonce()
        );

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(this)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(currentTxHash.length),
            currentTxHash
        );

        (success) = IGnosisSafe(safe).execTransaction(
            _to,
            _value,
            _data,
            Enum.Operation.Call,
            _safeTxGas,
            _baseGas,
            _gasPrice,
            _gasToken,
            _refundReceiver,
            signature
        );

        isExecuting = false;
        currentTxHash = bytes32(0);

        if (!success) revert DelegationOwner__execTransaction_notSuccess();
    }

    /**
     * @notice Validates that the signer is the current signature delegatee, or a valid transaction executed by a asset
     * delegatee.
     * @param _data Hash of the data signed on the behalf of address(msg.sender) which must be encoded as bytes,
     * necessary to make it compatible how the Safe calls the function.
     * @param _signature Signature byte array associated with _dataHash
     */
    function isValidSignature(bytes calldata _data, bytes calldata _signature) public view override returns (bytes4) {
        if (!isExecuting) {
            if (!_isDelegating(signatureDelegation)) revert DelegationOwner__isValidSignature_notDelegated();
            // CompatibilityFallbackHandler encodes the bytes32 dataHash before calling the old version of isValidSignature
            bytes32 dataHash = abi.decode(_data, (bytes32));
            address signer = ECDSA.recover(dataHash, _signature);
            if (signatureDelegation.delegatee != signer) revert DelegationOwner__isValidSignature_invalidSigner();
        } else {
            bytes32 txHash = abi.decode(_signature, (bytes32));
            if (txHash != currentTxHash) revert DelegationOwner__isValidSignature_invalidExecSig();
        }

        return EIP1271_MAGIC_VALUE;
    }

    /**
     * @notice Checks that a function is allowed to be executed by a delegatee of a given asset.
     */
    function isAllowedFunction(
        address _asset,
        address _contract,
        bytes4 _selector
    ) public view returns (bool) {
        return recipes.isAllowedFunction(_asset, _contract, _selector);
    }

    /**
     * @notice Sets an asset as locked.
     */
    function lockAsset(address _asset, uint256 _id, uint256 _claimDate) external onlyLockController {
        _checkGuardConfigured();
        _checkOwnedAndNotApproved(_asset, _id);

        bytes32 id = assetId(_asset, _id);
        if (lockedAssets[id] > 0)  revert DelegationOwner__lockAsset_assetLocked();
        if (_claimDate < block.timestamp ) revert DelegationOwner__lockAsset_invalidClaimDate();

        Delegation storage delegation = delegations[id];

        if (_isDelegating(delegation) && delegation.to > _claimDate) revert DelegationOwner__lockAsset_assetDelegatedLonger();
        if (
            _isDelegating(signatureDelegation) &&
            signatureDelegationAssets[currentSignatureDelegationAssets].contains(id) &&
            signatureDelegation.to > _claimDate
        ) revert DelegationOwner__lockAsset_signatureDelegatedLonger();

        lockedAssets[id] = _claimDate;
        guard.lockAsset(_asset, _id);

        emit LockedAsset(_asset, _id);
    }

    /**
     * @notice Sets an asset as unlocked.
     */
    function unlockAsset(address _asset, uint256 _id) external onlyLockController {
        // safe should be owner
        if (IERC721(_asset).ownerOf(_id) != safe) revert DelegationOwner__unlockAsset_assetNotOwned();

        emit UnlockedAsset(_asset, _id);

        lockedAssets[assetId(_asset, _id)] = 0;
        guard.unlockAsset(_asset, _id);
    }

    /**
     * @notice Sends a locked asset to the `receiver`.
     */
    function claimAsset(
        address _asset,
        uint256 _id,
        address _receiver
    ) external onlyLockController {
        uint256 claimDate = lockedAssets[assetId(_asset, _id)];
        if (claimDate == 0 || claimDate > block.timestamp) revert DelegationOwner__claimAsset_assetNotClaimable();

        guard.unlockAsset(_asset, _id);

        bool success = _transferAsset(_asset, _id, _receiver);

        if (!success) revert DelegationOwner__claimAsset_notSuccess();

        emit ClaimedAsset(_asset, _id, _receiver);
    }

    /**
     * @notice Returns if an asset is locked.
     */
    function isAssetLocked(address _asset, uint256 _id) external view returns (bool) {
        return guard.isLocked(_asset, _id);
    }

    /**
     * @notice Returns if an asset is delegated.
     */
    function isAssetDelegated(address _asset, uint256 _id) external view returns (bool) {
        return _isDelegating(delegations[assetId(_asset, _id)]);
    }

    /**
     * @notice Returns if the signature is delegated.
     */
    function isSignatureDelegated() external view returns (bool) {
        return _isDelegating(signatureDelegation);
    }

    function assetId(address _asset, uint256 _id) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_asset, _id));
    }

    function _getSelector(bytes memory _data) internal pure returns (bytes4 selector) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(_data, 32))
        }
    }

    function _isDelegating(Delegation storage _delegation) internal view returns (bool) {
        return (_delegation.from <= block.timestamp && block.timestamp <= _delegation.to);
    }

    function _getAllowedFunctionsKey(Delegation storage _delegation) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_delegation.delegatee, _delegation.from, _delegation.to));
    }

    function _checkGuardConfigured() internal view {
        bytes memory storageAt = GnosisSafe(payable(safe)).getStorageAt(uint256(GUARD_STORAGE_SLOT), 1);
        address configuredGuard = abi.decode(storageAt, (address));
        if (configuredGuard != address(guard)) revert DelegationOwner__checkGuardConfigured_noGuard();
    }

    function _checkOwnedAndNotApproved(address _asset, uint256 _id) internal view {
        // safe should be owner
        if (IERC721(_asset).ownerOf(_id) != safe) revert DelegationOwner__checkOwnedAndNotApproved_assetNotOwned();
        // asset shouldn't be approved, it won't be possible to prevent the approved address to move the asset out of the safe
        if (IERC721(_asset).getApproved(_id) != address(0)) revert DelegationOwner__checkOwnedAndNotApproved_assetApproved();
    }

    function _setupGuard(address _safe, DelegationGuard _guard) internal {
        // this requires this address to be a owner of the safe already
        isExecuting = true;
        bytes memory payload = abi.encodeWithSelector(IGnosisSafe.setGuard.selector, _guard);
        currentTxHash = IGnosisSafe(payable(_safe)).getTransactionHash(
            // Transaction info
            safe,
            0,
            payload,
            Enum.Operation.Call,
            0,
            // Payment info
            0,
            0,
            address(0),
            payable(0),
            // Signature info
            IGnosisSafe(payable(_safe)).nonce()
        );

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(this)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(currentTxHash.length),
            currentTxHash
        );

        IGnosisSafe(_safe).execTransaction(
            safe,
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signature
        );

        isExecuting = false;
        currentTxHash = bytes32(0);
    }

    /**
     * @notice Transfer an asset owned by the safe.
     */
    function _transferAsset(
        address _asset,
        uint256 _id,
        address _receiver
    ) internal returns (bool) {
        // safe should be owner
        if (IERC721(_asset).ownerOf(_id) != safe) revert DelegationOwner__transferAsset_assetNotOwned();

        bytes memory payload = abi.encodeWithSelector(IERC721.transferFrom.selector, safe, _receiver, _id);

        isExecuting = true;
        currentTxHash = IGnosisSafe(payable(safe)).getTransactionHash(
            _asset,
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            IGnosisSafe(payable(safe)).nonce()
        );

        // https://docs.gnosis-safe.io/contracts/signatures#contract-signature-eip-1271
        bytes memory signature = abi.encodePacked(
            abi.encode(address(this)), // r
            abi.encode(uint256(65)), // s
            bytes1(0), // v
            abi.encode(currentTxHash.length),
            currentTxHash
        );

        bool success = IGnosisSafe(safe).execTransaction(
            _asset,
            0,
            payload,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signature
        );

        isExecuting = false;
        currentTxHash = bytes32(0);

        return success;
    }
}
