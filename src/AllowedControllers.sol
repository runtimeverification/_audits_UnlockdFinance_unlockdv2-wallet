// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { Errors } from "./libs/helpers/Errors.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAllowedControllers } from "./interfaces/IAllowedControllers.sol";

/**
 * @title AllowedController
 * @author BootNode
 * @dev Registry for allowed addresses to be used as lock or delegation controllers in a DelegationWallet.
 */
contract AllowedControllers is IAllowedControllers, Ownable {
    /**
     * @notice A mapping from a collections address
     */
    mapping(address => bool) private allowedCollections;

    /**
     * @notice A mapping from a controllers address to whether that address is allowed to be used by a DelegationWallet
     * as a lock controller.
     */
    mapping(address => bool) private allowedLockControllers;

    /**
     * @notice A mapping from a controllers address to whether that address is allowed to be used by a DelegationWallet
     * as a delegation controller.
     */
    mapping(address => bool) private allowedDelegationControllers;

    /**
     * @notice Initialize `allowedLockControllers` and  `allowedDelegationControllers` with a batch of allowed
     * controllers.
     *
     * @param _lockControllers - The batch of lock controller addresses initially allowed.
     * @param _delegationControllers - The batch of delegation controller addresses initially allowed.
     */
    constructor(address[] memory _lockControllers, address[] memory _delegationControllers) {
        uint256 length = _lockControllers.length;
        for (uint256 i; i < length; ) {
            _setLockControllerAllowance(_lockControllers[i], true);
            unchecked {
                ++i;
            }
        }

        length = _delegationControllers.length;
        for (uint256 j; j < length; ) {
            _setDelegationControllerAllowance(_delegationControllers[j], true);
            unchecked {
                j++;
            }
        }
    }

    // ========== External functions ===========
    /**
     * @notice This function can be called by admins to change the allowance status of all the collections.
     *
     * @param _collection - The address of the collection.
     * @param _allowed - The new status of the collection.
     */
    function setCollectionAllowance(address _collection, bool _allowed) external onlyOwner {
        _setCollectionAllowance(_collection, _allowed);
    }

    /**
     * @notice This function can be called by admins to change the permitted status of a batch of multiple collections.
     *
     * @param _collections - The addresses of the collections.
     * @param _allowances - The new addresses of the collections.
     */
    function setCollectionsAllowances(address[] calldata _collections, bool[] calldata _allowances) external onlyOwner {
        if (_collections.length != _allowances.length)
            revert Errors.AllowedCollections__setCollectionsAllowances_arityMismatch();

        uint256 length = _collections.length;
        for (uint256 i; i < length; ) {
            _setCollectionAllowance(_collections[i], _allowances[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function can be called by admins to change the allowance status of a lock controller. This includes
     * both adding a controller to the allowed list and removing it.
     *
     * @param _controller - The address of the controller whose allowance list status changed.
     * @param _allowed - The new status of whether the controller is allowed or not.
     */
    function setLockControllerAllowance(address _controller, bool _allowed) external onlyOwner {
        _setLockControllerAllowance(_controller, _allowed);
    }

    /**
     * @notice This function can be called by admins to change the permitted status of a batch of lock controllers. This
     * both adding a controller to the allowed list and removing it.
     *
     * @param _controllers - The addresses of the controllers whose allowance list status changed.
     * @param _allowances - The new statuses of whether the controller is allowed or not.
     */
    function setLockControllerAllowances(
        address[] calldata _controllers,
        bool[] calldata _allowances
    ) external onlyOwner {
        if (_controllers.length != _allowances.length)
            revert Errors.AllowedControllers__setLockControllerAllowances_arityMismatch();

        uint256 length = _controllers.length;
        for (uint256 i; i < length; ) {
            _setLockControllerAllowance(_controllers[i], _allowances[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function can be called by admins to change the allowance status of a lock controller. This includes
     * both adding a controller to the allowed list and removing it.
     *
     * @param _controller - The address of the controller whose allowance list status changed.
     * @param _allowed - The new status of whether the controller is allowed or not.
     */
    function setDelegationControllerAllowance(address _controller, bool _allowed) external onlyOwner {
        _setDelegationControllerAllowance(_controller, _allowed);
    }

    /**
     * @notice This function can be called by admins to change the permitted status of a batch of delegation
     * controllers. This both adding a controller to the allowed list and removing it.
     *
     * @param _controllers - The addresses of the controllers whose allowance list status changed.
     * @param _allowances - The new statuses of whether the controller is allowed or not.
     */
    function setDelegationControllerAllowances(
        address[] calldata _controllers,
        bool[] calldata _allowances
    ) external onlyOwner {
        if (_controllers.length != _allowances.length)
            revert Errors.AllowedControllers__setDelegationControllerAllowances_arityMismatch();

        uint256 length = _controllers.length;
        for (uint256 i; i < length; ) {
            _setDelegationControllerAllowance(_controllers[i], _allowances[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Checks if an collection address is an allowed .
     *
     * @param _collection - The address of the controller.
     */
    function isAllowedCollection(address _collection) external view returns (bool) {
        if (_collection == address(0)) return false;
        return allowedCollections[_collection];
    }

    /**
     * @notice Checks if an address is an allowed lock controller.
     *
     * @param _controller - The address of the controller.
     */
    function isAllowedLockController(address _controller) external view returns (bool) {
        return allowedLockControllers[_controller];
    }

    /**
     * @notice Checks if an address is an allowed delegation controller.
     *
     * @param _controller - The address of the controller.
     */
    function isAllowedDelegationController(address _controller) external view returns (bool) {
        return allowedDelegationControllers[_controller];
    }

    /**
     * @notice Changes the allowance status of an lock controller. This includes both adding a controller to the
     * allowed list and removing it.
     *
     * @param _collection - The address of the controller whose allowance list status changed.
     * @param _allowed - The new status of whether the controller is allowed or not.
     */
    function _setCollectionAllowance(address _collection, bool _allowed) internal {
        if (_collection == address(0)) revert Errors.AllowedCollections__setCollectionsAllowances_invalidAddress();

        allowedCollections[_collection] = _allowed;

        emit Collections(_collection, _allowed);
    }

    /**
     * @notice Changes the allowance status of an lock controller. This includes both adding a controller to the
     * allowed list and removing it.
     *
     * @param _lockController - The address of the controller whose allowance list status changed.
     * @param _allowed - The new status of whether the controller is allowed or not.
     */
    function _setLockControllerAllowance(address _lockController, bool _allowed) internal {
        if (_lockController == address(0))
            revert Errors.AllowedControllers__setLockControllerAllowance_invalidAddress();

        allowedLockControllers[_lockController] = _allowed;

        emit LockController(_lockController, _allowed);
    }

    /**
     * @notice Changes the allowance status of an delegation controller. This includes both adding a controller to the
     * allowed list and removing it.
     *
     * @param _delegationController - The address of the controller whose allowance list status changed.
     * @param _allowed - The new status of whether the controller is allowed or not.
     */
    function _setDelegationControllerAllowance(address _delegationController, bool _allowed) internal {
        if (_delegationController == address(0))
            revert Errors.AllowedControllers__setDelegationControllerAllowance_invalidAddress();

        allowedDelegationControllers[_delegationController] = _allowed;

        emit DelegationController(_delegationController, _allowed);
    }
}
