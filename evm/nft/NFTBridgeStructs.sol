// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract NFTBridgeStructs {

    struct Transfer {
        // PayloadID uint8 = 1
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // Symbol of the token
        bytes32 symbol;
        // Name of the token
        bytes32 name;
        // TokenID for 721
        uint256 tokenID;
        // Token Type of the token, 1 for 721, 2 for 1155
        uint8 tokenType;
        // TokenID of the token
        uint256[] tokenIDs;
        // TokenID of the token
        uint256[] tokenAmounts;
        // Royalty Address
        bytes32 royaltyAddress;
        // Royalty Bips
        uint96 royaltyFees;
        // Rent Address
        bytes32 rentAddress;
        // Rent Timestamp;
        uint256 rentExpiryDate;
        // URI of the token metadata (UTF-8)
        string uri;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        bytes32 to;
        // Chain ID of the recipient
        uint16 toChain;
        // additional data for constructor
        bytes data;
        // additional data for bridgeMint
        bytes mintData;
    }

    struct RegisterChain {
        // Governance Header
        // module: "NFTBridge" left-padded
        bytes32 module;
        // governance action: 1
        uint8 action;
        // governance paket chain id: this or 0
        uint16 chainId;

        // Chain ID
        uint16 emitterChainID;
        // Emitter address. Left-zero-padded if shorter than 32 bytes
        bytes32 emitterAddress;
    }

    struct UpgradeContract {
        // Governance Header
        // module: "NFTBridge" left-padded
        bytes32 module;
        // governance action: 2
        uint8 action;
        // governance paket chain id
        uint16 chainId;

        // Address of the new contract
        bytes32 newContract;
    }
}
