// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract TestNftPlatform {
    IERC721 public nft;
    uint256 public count;

    modifier onlyNftOwner() {
        require(nft.balanceOf(msg.sender) > 0, "not collection owner");
        _;
    }

    constructor(address _nft) {
        nft = IERC721(_nft);
    }

    function allowedFunction() external onlyNftOwner {
        count += 1;
    }

    function notAllowedFunction() external onlyNftOwner {
        count += 1;
    }
}
