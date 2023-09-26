// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;


contract GuardManager {
    bool public isGuardSet = false;
    
    function setGuardIfNotSet(address safe, address guard) external {
        require(!isGuardSet, "Guard has already been set");

        // Logic to set the guard on the safe
        // This could be a direct call or a delegatecall depending on your needs

        isGuardSet = true;
    }
}