// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../interfaces/ICryptoPunks.sol";

contract TestPunks is ICryptoPunks {
    string public standard = "CryptoPunks";
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    uint256 public punksRemainingToAssign = 0;

    // A record of punks that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping(uint256 => Offer) internal _punksOfferedForSale;

    //mapping (address => uint) public addressToPunkIndex;
    mapping(uint256 => address) public override punkIndexToAddress;

    /* This creates an array with all balances */
    mapping(address => uint256) public override balanceOf;

    mapping(address => uint256) public pendingWithdrawals;

    event Assign(address indexed to, uint256 punkIndex);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PunkTransfer(address indexed from, address indexed to, uint256 punkIndex);
    event PunkOffered(uint256 indexed punkIndex, uint256 minValue, address indexed toAddress);
    event PunkBought(uint256 indexed punkIndex, uint256 value, address indexed fromAddress, address indexed toAddress);
    event PunkNoLongerForSale(uint256 indexed punkIndex);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    constructor() payable {
        totalSupply = 10000; // Update total supply
        punksRemainingToAssign = totalSupply;
        name = "CRYPTOPUNKS"; // Set the name for display purposes
        symbol = "C"; // Set the symbol for display purposes
        decimals = 0; // Amount of decimals for display purposes
    }

    function punksOfferedForSale(uint256 punkIndex) external view override returns (Offer memory) {
        return _punksOfferedForSale[punkIndex];
    }

    function mint(address to, uint256 punkIndex) public {
        require(punkIndex < 10000, "index >= 10000");
        if (punkIndexToAddress[punkIndex] != to) {
            if (punkIndexToAddress[punkIndex] != address(0)) {
                balanceOf[punkIndexToAddress[punkIndex]]--;
            } else {
                punksRemainingToAssign--;
            }
            punkIndexToAddress[punkIndex] = to;
            balanceOf[to]++;
            emit Assign(to, punkIndex);
        }
    }

    // Transfer ownership of a punk to another user without requiring payment
    function transferPunk(address to, uint256 punkIndex) external {
        require(punkIndexToAddress[punkIndex] == msg.sender, "sender not owner");
        require(punkIndex < 10000, "index >= 10000");
        punkIndexToAddress[punkIndex] = to;
        balanceOf[msg.sender]--;
        balanceOf[to]++;
        emit Transfer(msg.sender, to, 1);
        emit PunkTransfer(msg.sender, to, punkIndex);
    }

    function offerPunkForSale(uint punkIndex, uint minSalePriceInWei) external {
        require(punkIndexToAddress[punkIndex] == msg.sender, "sender not owner");
        require(punkIndex < 10000, "index >= 10000");
        _punksOfferedForSale[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, address(0));
        emit PunkOffered(punkIndex, minSalePriceInWei, address(0));
    }

    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external {
        require(punkIndexToAddress[punkIndex] == msg.sender, "sender not owner");
        require(punkIndex < 10000, "index >= 10000");
        _punksOfferedForSale[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, toAddress);
        emit PunkOffered(punkIndex, minSalePriceInWei, toAddress);
    }

    function punkNoLongerForSale(uint256 punkIndex) external {
        require(punkIndexToAddress[punkIndex] == msg.sender, "sender not owner");
        require(punkIndex < 10000, "index >= 10000");
        _punksOfferedForSale[punkIndex] = Offer(false, punkIndex, msg.sender, 0, address(0));
        emit PunkNoLongerForSale(punkIndex);
    }
}
