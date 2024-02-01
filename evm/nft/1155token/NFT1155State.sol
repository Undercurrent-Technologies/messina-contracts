// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract NFT1155Storage {

    struct State {
        // Mapping owner address to token count
        mapping(uint256 => mapping(address => uint256)) balances;
        // Mapping from owner to operator approvals
        mapping(address => mapping(address => bool)) operatorApprovals;
        // Mapping from tokenID to createData
        mapping(uint256 => bytes) tokenData;

        // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
        string uri;

        address owner;
        address nftBridge;
        bool initialized;
        uint16 chainId;
        uint16 standardID;
        bytes32 nativeContract;
        // additional data
        bytes data;
    }
}

contract NFTState1155 {
    NFT1155Storage.State internal state;
}
