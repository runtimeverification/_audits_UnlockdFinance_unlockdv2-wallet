// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC165 } from "@gnosis.pm/safe-contracts/contracts/interfaces/IERC165.sol";
import { Guard } from "@gnosis.pm/safe-contracts/contracts/base/GuardManager.sol";
import { OwnerManager, GuardManager } from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { DelegationOwner } from "../owners/DelegationOwner.sol";
import { ICryptoPunks } from "../../interfaces/ICryptoPunks.sol";
import { IGnosisSafe } from "../../interfaces/IGnosisSafe.sol";
import { AssetLogic } from "../logic/AssetLogic.sol";
import { Errors } from "../helpers/Errors.sol";

contract ProtocolGuard is Guard, Initializable {
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256)")));
    bytes4 internal constant ERC721_SAFE_TRANSFER_FROM_DATA =
        bytes4(keccak256(bytes("safeTransferFrom(address,address,uint256,bytes)")));

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {}

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
        // NOTHING TO DO
    }

    /**
     * @notice This function is called from Safe.execTransaction to perform checks after executing the transaction.
     */
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
        // NOTHING TO DO
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
