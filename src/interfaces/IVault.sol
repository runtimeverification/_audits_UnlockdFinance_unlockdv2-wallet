// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

interface INFTVault {
    // Events

    event RescueToken(address indexed collection, uint256 indexed tokenId, uint256 tokenIndex, address to);

    event AssignLoanNFT(uint256 indexed tokenIndex, uint256 loanId);
    event ChangeOwnerNFT(uint256 indexed tokenIndex, address indexed oldOwner, address indexed newOwner);

    function claimAsset(address nftAsset, uint256 id) external;

    function totalAssets() external returns (uint256);

    function deposit(address[] calldata nftAssets, uint256[] calldata ids) external;

    function ownerOf(uint256 index) external returns (address);

    function isStaked(address nftAsset, uint256 tokenId) external returns (bool);

    function tokenIndex(address nftAsset, uint256 tokenId) external returns (bytes32);

    function getLoanId(bytes32 index) external returns (uint256);

    function setLoanId(bytes32 index, uint256 loanId) external;

    function changeOwner(bytes32 index, address owner) external;

    function batchSetLoanId(address[] calldata nftAsset, uint256[] calldata id, uint256 loanId) external;

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);

    function rescueToken(address nftAsset, uint256 tokenId, address newOwner) external;
}
