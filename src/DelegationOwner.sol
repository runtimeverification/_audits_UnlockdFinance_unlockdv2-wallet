// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { IGnosisSafe } from "./interfaces/IGnosisSafe.sol";
import { ICryptoPunks } from "./interfaces/ICryptoPunks.sol";
import { IAllowedControllers } from "./interfaces/IAllowedControllers.sol";
import { IACLManager } from "./interfaces/IACLManager.sol";
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

    address public immutable cryptoPunks;

    /**
     * @notice The DelegationRecipes address.
     */
    DelegationRecipes public immutable recipes;

    /**
     * @notice The AllowedControllers address.
     */
    IAllowedControllers public immutable allowedControllers;

    /**
     * @notice The ACLManager address.
     */
    IACLMAnager public immutable aclManager;

    /**
     * @notice Delegation information, it is used for assets and signatures.
     *
     * @param controller - The delegation controller address that created the delegations.
     * @param delegatee - The delegatee address.
     * @param from - The date (seconds timestamp) when the delegation starts.
     * @param to - The date (seconds timestamp) when the delegation ends.
     */
    struct Delegation {
        address controller;
        address delegatee;
        uint256 from;
        uint256 to;
    }

    /**
     * @notice Safe wallet address.
     */
    address public safe;

    /**
     * @notice The owner of the DelegationWallet, it is set only once upon initialization. Since this contract works
     * in tandem with DelegationGuard which do not allow to change the Safe owners, this owner can't change neither.
     */
    address public owner;

    /**
     * @notice The delegation controller address. Allowed to execute delegation related functions.
     */
    mapping(address => bool) public delegationControllers;

    /**
     * @notice The lock controller address. Allowed to execute asset locking related functions.
     */
    mapping(address => bool) public lockControllers;

    /**
     * @notice The DelegationGuard address.
     */
    DelegationGuard public guard;

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
     * @notice List of assetIds affected by last signatureDelegation. This is used for cheap checking if asset in
     * included in current signature delegation.
     */
    mapping(uint256 => EnumerableSet.Bytes32Set) private signatureDelegationAssetsIds;

    struct SignatureAssets {
        address[] assets;
        uint256[] ids;
    }

    /**
     * @notice List of assets and ids affected by last signatureDelegation. This is used mainly when ending the
     * signature delegation to  be able to set the expiry of each asset on the guard. Using EnumerableSet.values from
     * signatureDelegationAssetsIds may render the function uncallable if the set grows to a point where copying to
     * memory consumes too much gas to fit in a block.
     */
    mapping(uint256 => SignatureAssets) private signatureDelegationAssets;

    /**
     * @notice Current signature delegation id
     */
    uint256 private currentSignatureDelegationAssets;

    /**
     * @notice Stores for each locked assets the date since it turns claimable. keccak256(address, nft id) => claimDate
     */
    mapping(bytes32 => uint256) public lockedAssets;

    /**
     * @notice Stores for each locked assets the lock controller address
     */
    mapping(bytes32 => address) public lockedBy;

    // ========== Events ===========

    event SetDelegationController(address indexed delegationController, bool allowed);
    event SetLockController(address indexed lockController, bool allowed);
    event NewDelegation(
        address indexed asset,
        uint256 indexed assetId,
        uint256 from,
        uint256 to,
        address indexed delegatee,
        address delegationController
    );
    event EndDelegation(address indexed asset, uint256 indexed assetId, address delegationController);
    event DelegatedSignature(
        uint256 from,
        uint256 to,
        address indexed delegatee,
        address[] assets,
        uint256[] assetIds,
        address delegationController
    );
    event EndDelegatedSignature(address[] assets, uint256[] assetIds, address delegationController);
    event LockedAsset(
        address indexed asset,
        uint256 indexed assetId,
        uint256 claimDate,
        address indexed lockController
    );
    event ChangeClaimDate(
        address indexed asset,
        uint256 indexed assetId,
        uint256 claimDate,
        address indexed lockController
    );
    event UnlockedAsset(address indexed asset, uint256 indexed assetId, address indexed lockController);
    event ClaimedAsset(address indexed asset, uint256 indexed assetId, address indexed receiver);
    event TransferredAsset(address indexed asset, uint256 indexed assetId, address indexed receiver);

    // ========== Custom Errors ===========
    error DelegationGuard__initialize_invalidGuardBeacon();
    error DelegationGuard__initialize_invalidRecipes();
    error DelegationGuard__initialize_invalidSafe();
    error DelegationGuard__initialize_invalidOwner();

    error DelegationOwner__onlyOwner();
    error DelegationOwner__onlyDelegationController();
    error DelegationOwner__onlyLockController();
    error DelegationOwner__onlyDelegationCreator();
    error DelegationOwner__onlySignatureDelegationCreator();
    error DelegationOwner__onlyLockCreator();

    error DelegationOwner__delegate_currentlyDelegated();
    error DelegationOwner__delegate_invalidDelegatee();
    error DelegationOwner__delegate_invalidDuration();
    error DelegationOwner__delegate_invalidExpiry();

    error DelegationOwner__delegateSignature_invalidExpiry(address asset, uint256 id);
    error DelegationOwner__delegateSignature_invalidArity();
    error DelegationOwner__delegateSignature_currentlyDelegated();
    error DelegationOwner__delegateSignature_invalidDelegatee();
    error DelegationOwner__delegateSignature_invalidDuration();
    error DelegationOwner__endDelegateSignature_invalidArity();

    error DelegationOwner__isValidSignature_notDelegated();
    error DelegationOwner__isValidSignature_invalidSigner();
    error DelegationOwner__isValidSignature_invalidExecSig();

    error DelegationOwner__execTransaction_notDelegated();
    error DelegationOwner__execTransaction_invalidDelegatee();
    error DelegationOwner__execTransaction_notAllowedFunction();
    error DelegationOwner__execTransaction_notSuccess();

    error DelegationOwner__lockAsset_assetLocked();
    error DelegationOwner__lockAsset_invalidClaimDate();

    error DelegationOwner__changeClaimDate_invalidClaimDate();

    error DelegationOwner__claimAsset_assetNotClaimable();
    error DelegationOwner__claimAsset_assetNotLocked();
    error DelegationOwner__claimAsset_notSuccess();

    error DelegationOwner__transferAsset_assetNotOwned();

    error DelegationOwner__checkOwnedAndNotApproved_assetNotOwned();
    error DelegationOwner__checkOwnedAndNotApproved_assetApproved();

    error DelegationOwner__checkClaimDate_assetDelegatedLonger();
    error DelegationOwner__checkClaimDate_signatureDelegatedLonger();

    error DelegationOwner__lockCreatorChecks_assetNotLocked();
    error DelegationOwner__lockCreatorChecks_onlyLockCreator();

    error DelegationOwner__delegationCreatorChecks_notDelegated();
    error DelegationOwner__delegationCreatorChecks_onlyDelegationCreator();

    error DelegationOwner__setDelegationController_notAllowedController();
    error DelegationOwner__setLockController_notAllowedController();

    /**
     * @notice This modifier indicates that only the Delegation Controller can execute a given function.
     */
    modifier onlyOwner() {
        if (owner != msg.sender) revert DelegationOwner__onlyOwner();
        _;
    }

    /**
     * @notice This modifier indicates that only the Delegation Controller can execute a given function.
     */
    modifier onlyDelegationController() {
        if (!delegationControllers[msg.sender]) revert DelegationOwner__onlyDelegationController();
        _;
    }

    /**
     * @notice This modifier indicates that only the Lock Controller can execute a given function.
     */
    modifier onlyLockController() {
        if (!lockControllers[msg.sender]) revert DelegationOwner__onlyLockController();
        _;
    }

    /**
     * @dev Disables the initializer in order to prevent implementation initialization.
     */
    constructor(address _cryptoPunks, address _recipes, address _allowedControllers, address _aclManager) {
        cryptoPunks = _cryptoPunks;
        recipes = DelegationRecipes(_recipes);
        allowedControllers = IAllowedControllers(_allowedControllers);
        aclManager = IACLManager(_aclManager);
        _disableInitializers();
    }

    /**
     * @notice Initializes the proxy state.
     * @param _guardBeacon - The address of the beacon where the proxy gets the implementation address.
     * @param _safe - The DelegationWallet address, the GnosisSafe.
     * @param _owner - The owner of the DelegationWallet.
     * @param _delegationController - The address that acts as the delegation controller.
     * @param _lockController - The address that acts as the lock controller.
     */
    function initialize(
        address _guardBeacon,
        address _safe,
        address _owner,
        address _delegationController,
        address _lockController
    ) public initializer {
        if (_guardBeacon == address(0)) revert DelegationGuard__initialize_invalidGuardBeacon();
        if (_safe == address(0)) revert DelegationGuard__initialize_invalidSafe();
        if (_owner == address(0)) revert DelegationGuard__initialize_invalidOwner();

        safe = _safe;
        owner = _owner;
        if (_delegationController != address(0)) {
            _setDelegationController(_delegationController, true);
        }
        if (_lockController != address(0)) {
            _setLockController(_lockController, true);
        }

        address guardProxy = address(
            new BeaconProxy(_guardBeacon, abi.encodeWithSelector(DelegationGuard.initialize.selector, address(this)))
        );
        guard = DelegationGuard(guardProxy);

        _setupGuard(_safe, guard);
    }

    /**
     * @notice Sets a delegation controller address as allowed or not.
     * @param _delegationController - The new delegation controller address.
     * @param _allowed - Allowance status.
     */
    function setDelegationController(address _delegationController, bool _allowed) external onlyOwner {
        _setDelegationController(_delegationController, _allowed);
    }

    /**
     * @notice Sets the lock controller address as allowed or not.
     * @param _lockController - The new lock controller address.
     * @param _allowed - Allowance status.
     */
    function setLockController(address _lockController, bool _allowed) external onlyOwner {
        _setLockController(_lockController, _allowed);
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
        _checkOwnedAndNotApproved(_asset, _id);

        bytes32 id = assetId(_asset, _id);
        Delegation storage delegation = delegations[id];

        if (_isDelegating(delegation)) revert DelegationOwner__delegate_currentlyDelegated();
        if (_delegatee == address(0)) revert DelegationOwner__delegate_invalidDelegatee();
        if (_duration == 0) revert DelegationOwner__delegate_invalidDuration();

        delegation.controller = msg.sender;
        delegation.delegatee = _delegatee;
        uint256 from = block.timestamp;
        uint256 to = block.timestamp + _duration;
        delegation.from = from;
        delegation.to = to;

        uint256 claimDate = lockedAssets[id];
        if (claimDate > 0 && claimDate < to) revert DelegationOwner__delegate_invalidExpiry();

        emit NewDelegation(_asset, _id, from, to, _delegatee, msg.sender);

        guard.setDelegationExpiry(_asset, _id, to);
    }

    /**
     * @notice Ends asset usage delegation.
     * @param _asset - The asset address.
     * @param _id - The asset id.
     */
    function endDelegate(address _asset, uint256 _id) external {
        Delegation storage delegation = delegations[assetId(_asset, _id)];
        _delegationCreatorChecks(delegation);

        delegation.to = 0;

        emit EndDelegation(_asset, _id, msg.sender);

        guard.setDelegationExpiry(_asset, _id, 0);
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
        if (_assets.length != _ids.length) revert DelegationOwner__delegateSignature_invalidArity();
        if (_isDelegating(signatureDelegation)) revert DelegationOwner__delegateSignature_currentlyDelegated();
        if (_delegatee == address(0)) revert DelegationOwner__delegateSignature_invalidDelegatee();
        if (_duration == 0) revert DelegationOwner__delegateSignature_invalidDuration();

        uint256 delegationExpiry = block.timestamp + _duration;

        currentSignatureDelegationAssets += 1;

        uint256 length = _assets.length;
        for (uint256 j; j < length; ) {
            _checkOwnedAndNotApproved(_assets[j], _ids[j]);

            bytes32 id = assetId(_assets[j], _ids[j]);
            uint256 claimDate = lockedAssets[id];
            if (claimDate > 0 && claimDate < delegationExpiry)
                revert DelegationOwner__delegateSignature_invalidExpiry(_assets[j], _ids[j]);

            signatureDelegationAssets[currentSignatureDelegationAssets].assets.push(_assets[j]);
            signatureDelegationAssets[currentSignatureDelegationAssets].ids.push(_ids[j]);
            signatureDelegationAssetsIds[currentSignatureDelegationAssets].add(id);

            unchecked {
                ++j;
            }
        }

        Delegation memory newDelegation = Delegation(msg.sender, _delegatee, block.timestamp, delegationExpiry);

        signatureDelegation = newDelegation;

        emit DelegatedSignature(newDelegation.from, newDelegation.to, _delegatee, _assets, _ids, msg.sender);

        guard.setDelegationExpiries(_assets, _ids, delegationExpiry);
    }

    /**
     * @notice Ends the delegation of the usage of the signature for the `_delegatee`. Unlocking a group of assets.
     */
    function endDelegateSignature() external {
        _delegationCreatorChecks(signatureDelegation);

        signatureDelegation.to = 0;

        emit EndDelegatedSignature(
            signatureDelegationAssets[currentSignatureDelegationAssets].assets,
            signatureDelegationAssets[currentSignatureDelegationAssets].ids,
            msg.sender
        );

        guard.setDelegationExpiries(
            signatureDelegationAssets[currentSignatureDelegationAssets].assets,
            signatureDelegationAssets[currentSignatureDelegationAssets].ids,
            0
        );
    }

    /**
     * @notice Execute a transaction through the GnosisSafe wallet.
     * The sender should be the delegatee of the given asset and the function should be allowed for the collection.
     * @param _asset - The delegated asset addresses.
     * @param _id - The delegated asset ids.
     * @param _to - Destination address of Safe transaction.
     * @param _value - Ether value of Safe transaction.
     * @param _data - Data payload of Safe transaction.
     * @param _safeTxGas - Gas that should be used for the Safe transaction.
     * @param _baseGas Gas costs that are independent of the transaction execution(e.g. base transaction fee, signature
     * check, payment of the refund)
     * @param _gasPrice - Gas price that should be used for the payment calculation.
     * @param _gasToken - Token address (or 0 if ETH) that is used for the payment.
     * @param _refundReceiver - Address of receiver of gas payment (or 0 if tx.origin).
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
    function isValidSignature(bytes memory _data, bytes memory _signature) public view override returns (bytes4) {
        if (!isExecuting) {
            if (!_isDelegating(signatureDelegation)) revert DelegationOwner__isValidSignature_notDelegated();
            // CompatibilityFallbackHandler encodes the bytes32 dataHash before calling the old version of i
            // sValidSignature
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
     * @param _asset - The delegated asset addresses.
     * @param _contract - The addresses of the destination contract.
     * @param _selector - The selector of the destination function.
     */
    function isAllowedFunction(address _asset, address _contract, bytes4 _selector) public view returns (bool) {
        return recipes.isAllowedFunction(_asset, _contract, _selector);
    }

    /**
     * @notice Sets an asset as locked.
     * @param _asset - The locked asset addresses.
     * @param _id - The locked asset id.
     * @param _claimDate - The date from which the asset could be claimed if it is also delegated.
     */
    function lockAsset(address _asset, uint256 _id, uint256 _claimDate) external onlyLockController {
        _checkOwnedAndNotApproved(_asset, _id);

        bytes32 id = assetId(_asset, _id);

        if (lockedAssets[id] != 0) revert DelegationOwner__lockAsset_assetLocked();
        if (_claimDate < block.timestamp) revert DelegationOwner__lockAsset_invalidClaimDate();

        _checkClaimDate(id, _claimDate);

        lockedAssets[id] = _claimDate;
        lockedBy[id] = msg.sender;
        guard.lockAsset(_asset, _id);

        emit LockedAsset(_asset, _id, _claimDate, msg.sender);
    }

    /**
     * @notice Updates the claimDate for a locked asset.
     * @param _asset - The locked asset addresses.
     * @param _id - The locked asset id.
     * @param _claimDate - The date from which the asset could be claimed if it is also delegated.
     */
    function changeClaimDate(address _asset, uint256 _id, uint256 _claimDate) external {
        bytes32 id = assetId(_asset, _id);
        _lockCreatorChecks(id);

        if (_claimDate < block.timestamp) revert DelegationOwner__changeClaimDate_invalidClaimDate();

        _checkClaimDate(id, _claimDate);

        lockedAssets[id] = _claimDate;

        emit ChangeClaimDate(_asset, _id, _claimDate, msg.sender);
    }

    /**
     * @notice Sets an asset as unlocked.
     * @param _asset - The locked asset addresses.
     * @param _id - The locked asset id.
     */
    function unlockAsset(address _asset, uint256 _id) external {
        bytes32 id = assetId(_asset, _id);
        _lockCreatorChecks(id);

        lockedAssets[id] = 0;
        lockedBy[id] = address(0);
        guard.unlockAsset(_asset, _id);

        emit UnlockedAsset(_asset, _id, msg.sender);
    }

    /**
     * @notice Sends a locked asset to the `receiver`.
     * @param _asset - The locked asset addresses.
     * @param _id - The locked asset id.
     * @param _receiver - The receiving address.
     */
    function claimAsset(address _asset, uint256 _id, address _receiver) external {
        bytes32 id = assetId(_asset, _id);
        _lockCreatorChecks(id);

        if (lockedAssets[id] > block.timestamp && _isAssetDelegated(id))
            revert DelegationOwner__claimAsset_assetNotClaimable();

        lockedAssets[id] = 0;
        lockedBy[id] = address(0);
        guard.unlockAsset(_asset, _id);

        bool success = _transferAsset(_asset, _id, _receiver);

        if (!success) revert DelegationOwner__claimAsset_notSuccess();

        emit ClaimedAsset(_asset, _id, _receiver);
    }

    /**
     * @notice Returns if an asset is locked.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function isAssetLocked(address _asset, uint256 _id) external view returns (bool) {
        return guard.isLocked(_asset, _id);
    }

    /**
     * @notice Returns if an asset is delegated or included in current signature delegation.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function isAssetDelegated(address _asset, uint256 _id) external view returns (bool) {
        return _isAssetDelegated(assetId(_asset, _id));
    }

    /**
     * @notice Returns if the signature is delegated.
     */
    function isSignatureDelegated() external view returns (bool) {
        return _isDelegating(signatureDelegation);
    }

    /**
     * @notice Returns internal identification of an asset.
     * @param _asset - The asset addresses.
     * @param _id - The asset id.
     */
    function assetId(address _asset, uint256 _id) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_asset, _id));
    }

    // ========== Internal functions ===========

    function _setDelegationController(address _delegationController, bool _allowed) internal {
        if (_allowed && !allowedControllers.isAllowedDelegationController(_delegationController))
            revert DelegationOwner__setDelegationController_notAllowedController();
        delegationControllers[_delegationController] = _allowed;
        emit SetDelegationController(_delegationController, _allowed);
    }

    function _setLockController(address _lockController, bool _allowed) internal {
        if (_allowed && !allowedControllers.isAllowedLockController(_lockController))
            revert DelegationOwner__setLockController_notAllowedController();
        lockControllers[_lockController] = _allowed;
        emit SetLockController(_lockController, _allowed);
    }

    function _getSelector(bytes memory _data) internal pure returns (bytes4 selector) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(_data, 32))
        }
    }

    function _isAssetDelegated(bytes32 _id) internal view returns (bool) {
        Delegation storage delegation = delegations[_id];
        return (_isDelegating(delegation) ||
            (_isDelegating(signatureDelegation) &&
                signatureDelegationAssetsIds[currentSignatureDelegationAssets].contains(_id)));
    }

    function _isDelegating(Delegation storage _delegation) internal view returns (bool) {
        return (_delegation.from <= block.timestamp && block.timestamp <= _delegation.to);
    }

    function _getAllowedFunctionsKey(Delegation storage _delegation) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_delegation.delegatee, _delegation.from, _delegation.to));
    }

    function _checkOwnedAndNotApproved(address _asset, uint256 _id) internal view {
        if (_asset == cryptoPunks) {
            // safe should be owner
            if (ICryptoPunks(_asset).punkIndexToAddress(_id) != safe)
                revert DelegationOwner__checkOwnedAndNotApproved_assetNotOwned();
            // asset shouldn't be approved, it won't be possible to prevent the approved address to move the asset out
            // of the safe
            if (ICryptoPunks(_asset).punksOfferedForSale(_id).isForSale)
                revert DelegationOwner__checkOwnedAndNotApproved_assetApproved();
        } else {
            // safe should be owner
            if (IERC721(_asset).ownerOf(_id) != safe) revert DelegationOwner__checkOwnedAndNotApproved_assetNotOwned();
            // asset shouldn't be approved, it won't be possible to prevent the approved address to move the asset out
            // f the safe
            if (IERC721(_asset).getApproved(_id) != address(0))
                revert DelegationOwner__checkOwnedAndNotApproved_assetApproved();
        }
    }

    function _checkClaimDate(bytes32 _id, uint256 _claimDate) internal view {
        Delegation storage delegation = delegations[_id];

        if (_isDelegating(delegation) && delegation.to > _claimDate)
            revert DelegationOwner__checkClaimDate_assetDelegatedLonger();
        if (
            _isDelegating(signatureDelegation) &&
            signatureDelegationAssetsIds[currentSignatureDelegationAssets].contains(_id) &&
            signatureDelegation.to > _claimDate
        ) revert DelegationOwner__checkClaimDate_signatureDelegatedLonger();
    }

    function _lockCreatorChecks(bytes32 _id) internal view {
        if (lockedAssets[_id] == 0) revert DelegationOwner__lockCreatorChecks_assetNotLocked();
        if (lockedBy[_id] != msg.sender) revert DelegationOwner__lockCreatorChecks_onlyLockCreator();
    }

    function _delegationCreatorChecks(Delegation storage _delegation) internal view {
        if (!_isDelegating(_delegation)) revert DelegationOwner__delegationCreatorChecks_notDelegated();
        if (_delegation.controller != msg.sender)
            revert DelegationOwner__delegationCreatorChecks_onlyDelegationCreator();
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
    function _transferAsset(address _asset, uint256 _id, address _receiver) internal returns (bool) {
        bytes memory payload = _asset == cryptoPunks
            ? _transferPunksPayload(_asset, _id, _receiver)
            : _transferERC721Payload(_asset, _id, _receiver);

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

    function _transferERC721Payload(
        address _asset,
        uint256 _id,
        address _receiver
    ) internal view returns (bytes memory) {
        // safe should be owner
        if (IERC721(_asset).ownerOf(_id) != safe) revert DelegationOwner__transferAsset_assetNotOwned();

        return abi.encodeWithSelector(IERC721.transferFrom.selector, safe, _receiver, _id);
    }

    function _transferPunksPayload(
        address _asset,
        uint256 _id,
        address _receiver
    ) internal view returns (bytes memory) {
        // safe should be owner
        if (ICryptoPunks(_asset).punkIndexToAddress(_id) != safe) revert DelegationOwner__transferAsset_assetNotOwned();

        return abi.encodeWithSelector(ICryptoPunks.transferPunk.selector, _receiver, _id);
    }
}
