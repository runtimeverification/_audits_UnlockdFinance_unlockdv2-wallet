// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { IGnosisSafe } from "./IGnosisSafe.sol";

interface IGnosisSafeProxyFactory {
    event ProxyCreation(IGnosisSafe proxy, address singleton);

    function createProxy(address singleton, bytes memory data) external returns (IGnosisSafe proxy);
}
