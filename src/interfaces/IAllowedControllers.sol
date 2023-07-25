// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

interface IAllowedControllers {
    // ========== Events ===========
    event Collections(address indexed collections, bool isAllowed);

    event LockController(address indexed lockController, bool isAllowed);

    event DelegationController(address indexed delegationController, bool isAllowed);

    function isAllowedLockController(address _controller) external view returns (bool);

    function isAllowedDelegationController(address _controller) external view returns (bool);

    function isAllowedCollection(address _collection) external view returns (bool);
}
