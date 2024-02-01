// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library CommonStructs {
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
        // StandardID for the NFT standard
        uint16 standardID;
        // Collection Owner Address
        bytes32 collectionOwner;
        // Token Type of the token, 1 for 721, 2 for 1155
        uint8 tokenType;
        // TokenID of the token
        uint256[] tokenIDs;
        // TokenID of the token
        uint256[] tokenAmounts;
        // Royalty Address
        bytes32 royaltyAddress;
        // Royalty Bips
        uint96 royaltyBips;
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

    struct NFTInitArgs {
        bytes4 selectorBytes;
        bytes data;
    }

    function hexToAscii(string memory hexStr)
        public
        pure
        returns (string memory)
    {
        bytes memory hexBytes = bytes(hexStr);
        bytes memory asciiBytes = new bytes(hexBytes.length / 2);
        uint256 j = 0;
        for (uint256 i = 0; i < hexBytes.length; i += 2) {
            uint256 hexValue = hexToUint(uint8(hexBytes[i])) *
                16 +
                hexToUint(uint8(hexBytes[i + 1]));
            asciiBytes[j++] = bytes1(uint8(hexValue));
        }
        return string(asciiBytes);
    }

    function hexToUint(uint8 b) private pure returns (uint256) {
        if (b >= uint8(bytes1("0")) && b <= uint8(bytes1("9"))) {
            return uint256(b) - uint8(bytes1("0"));
        }
        if (b >= uint8(bytes1("a")) && b <= uint8(bytes1("f"))) {
            return 10 + uint256(b) - uint8(bytes1("a"));
        }
        if (b >= uint8(bytes1("A")) && b <= uint8(bytes1("F"))) {
            return 10 + uint256(b) - uint8(bytes1("A"));
        }
        revert("Invalid hex character");
    }
}
