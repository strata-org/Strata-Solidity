// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Minimal ERC721-like NFT with NatSpec verification specs.
contract ERC721Spec {

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;

    /// @custom:strata ensures ownerOf[tokenId] == to
    /// @custom:strata ensures balanceOf[to] == old(balanceOf[to]) + 1
    function mint(address to, uint256 tokenId) external {
        require(to != address(0), "mint to zero address");
        require(ownerOf[tokenId] == address(0), "token already minted");
        ownerOf[tokenId] = to;
        balanceOf[to] += 1;
    }

    /// @custom:strata requires ownerOf[tokenId] == msg.sender
    /// @custom:strata ensures ownerOf[tokenId] == to
    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "not owner");
        require(to != address(0), "transfer to zero address");
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        ownerOf[tokenId] = to;
    }
}
