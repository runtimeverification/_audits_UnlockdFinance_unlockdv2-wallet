// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IDelegationOwner {
    // Delegation Controller Functions
    function delegate(address _asset, uint256 _assetId, address _delegatee, uint256 _duration) external;

    function endDelegate(address _asset, uint256 _assetId) external;

    function delegateSignature(
        address[] calldata _assets,
        uint256[] calldata _assetIds,
        address _delegatee,
        uint256 _duration
    ) external;

    function endDelegateSignature(address[] calldata _assets, uint256[] calldata _assetIds) external;

    // Lock Controller Functions
    function lockAsset(address _asset, uint256 _assetId, uint256 _claimDate) external;

    function changeClaimDate(address _asset, uint256 _id, uint256 _claimDate) external;

    function unlockAsset(address _asset, uint256 _assetId) external;

    function claimAsset(address _asset, uint256 _assetId, address _receiver) external;

    // Delegatee Functions
    function execTransaction(
        address _asset,
        uint256 _assetId,
        address _to,
        uint256 _value,
        bytes calldata _data,
        uint256 _safeTxGas,
        uint256 _baseGas,
        uint256 _gasPrice,
        address _gasToken,
        address payable _refundReceiver
    ) external returns (bool success);

    // View Functions
    function isValidSignature(bytes calldata _data, bytes calldata _signature) external view returns (bytes4);

    function isAllowedFunction(address _asset, address _contract, bytes4 _selector) external view returns (bool);

    function isAssetLocked(address _asset, uint256 _assetId) external view returns (bool);

    function isAssetDelegated(address _asset, uint256 _assetId) external view returns (bool);

    function isSignatureDelegated() external view returns (bool);

    function assetId(address _asset, uint256 _id) external view returns (bytes32);
}
