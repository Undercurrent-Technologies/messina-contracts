// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract NFTStorage {
    struct UserInfo {
        address user; // address of user role
        uint64 expires; // unix timestamp, user expires
    }

    struct State {
        // Token name
        string name;
        // Token symbol
        string symbol;
        // Mapping from token ID to owner address
        mapping(uint256 => address) owners;
        // Mapping owner address to token count
        mapping(address => uint256) balances;
        // Mapping from token ID to approved address
        mapping(uint256 => address) tokenApprovals;
        // Mapping from token ID to URI
        mapping(uint256 => string) tokenURIs;
        // Mapping from owner to operator approvals
        mapping(address => mapping(address => bool)) operatorApprovals;
        // Mapping from tokenID to createData
        mapping(uint256 => bytes) tokenData;
        
        address owner;
        address nftBridge;
        bool initialized;
        uint16 chainId;
        uint16 standardID;
        bytes32 nativeContract;
        bytes data;
    }
}

contract NFTState {
    NFTStorage.State internal state;
    // Mapping for users of ERC4907
    mapping(uint256 => NFTStorage.UserInfo) internal users;
}
