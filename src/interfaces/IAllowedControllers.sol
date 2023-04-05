// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IAllowedControllers {
    function isAllowedLockController(address _controller) external view returns (bool);

    function isAllowedDelegationController(address _controller) external view returns (bool);
}
