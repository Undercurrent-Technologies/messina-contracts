// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "./1155token/NFT1155Implementation.sol";
import "./token/NFTImplementation.sol";
import "./token/NFT.sol";

import "../libraries/external/BytesLib.sol";
import "../libraries/external/CommonStructs.sol";
import "../interfaces/INFTBridgeHelper.sol";

contract NFTBridgeHelper is INFTBridgeHelper {
    using BytesLib for bytes;
    using BytesLib for bytes32;
    using BytesLib for address;
    using CommonStructs for string;

    struct RoyaltyInfo {
        address royaltyAddress;
        uint96 royaltyBips;
    }

    struct WrappedNFTAssetArgs {
        uint16 tokenChain;
        bytes32 tokenAddress;
        bytes32 collectionOwner;
        bytes constructorArgs;
        bytes initialisationArgs;
        address beaconAddr;
        bytes4 selectorBytes;
        RoyaltyInfo royaltyInfo;
        uint16 standardID;
        bytes data;
    }

    function encodeTransfer(CommonStructs.Transfer memory transfer)
        external
        pure
        override
        returns (bytes memory result)
    {
        // There is a global limit on 200 bytes of tokenURI in Wormhole due to Solana
        require(
            bytes(transfer.uri).length <= 200,
            "tokenURI must not exceed 200 bytes"
        );

        bytes memory encoded0 = abi.encodePacked(
            uint8(1),
            transfer.tokenAddress,
            transfer.tokenChain,
            transfer.symbol,
            transfer.name,
            transfer.tokenID,
            transfer.standardID,
            transfer.collectionOwner
        );

        bytes memory encoded1 = abi.encodePacked(
            transfer.tokenType,
            uint16(transfer.tokenIDs.length),
            transfer.tokenIDs,
            uint16(transfer.tokenAmounts.length),
            transfer.tokenAmounts
        );

        bytes memory encoded2 = abi.encodePacked(
            transfer.royaltyAddress,
            transfer.royaltyBips,
            transfer.rentAddress,
            transfer.rentExpiryDate,
            uint16(abi.encodePacked(transfer.uri).length),
            abi.encodePacked(transfer.uri),
            transfer.to,
            transfer.toChain,
            uint16(transfer.data.length),
            transfer.data,
            uint16(transfer.mintData.length),
            transfer.mintData
        );

        result = bytes.concat(encoded0, encoded1, encoded2);
    }

    function parseTransfer(bytes memory encoded)
        external
        pure
        override
        returns (CommonStructs.Transfer memory transfer)
    {
        uint16 length;

        uint8 payloadID = encoded.toUint8(0);
        require(payloadID == 1, "invalid Transfer");

        uint256 index = 1;

        transfer.tokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.tokenChain = encoded.toUint16(index);
        index += 2;

        transfer.symbol = encoded.toBytes32(index);
        index += 32;

        transfer.name = encoded.toBytes32(index);
        index += 32;

        transfer.tokenID = encoded.toUint256(index);
        index += 32;

        transfer.standardID = encoded.toUint16(index);
        index += 2;

        transfer.collectionOwner = encoded.toBytes32(index);
        index += 32;

        transfer.tokenType = encoded.toUint8(index);
        index += 1;

        length = encoded.toUint16(index);
        index += 2;

        uint256[] memory tokenIDs = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokenIDs[i] = encoded.toUint256(index);
            index += 32;
        }

        transfer.tokenIDs = tokenIDs;

        length = encoded.toUint16(index);
        index += 2;

        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = encoded.toUint256(index);
            index += 32;
        }

        transfer.tokenAmounts = amounts;

        transfer.royaltyAddress = encoded.toBytes32(index);
        index += 32;

        transfer.royaltyBips = encoded.toUint96(index);
        index += 12;

        transfer.rentAddress = encoded.toBytes32(index);
        index += 32;

        transfer.rentExpiryDate = encoded.toUint256(index);
        index += 32;

        length = encoded.toUint16(index);
        index += 2;

        string memory hexStr = encoded.slice(index, length).hexString();
        transfer.uri = hexStr.hexToAscii();
        index += length;

        transfer.to = encoded.toBytes32(index);
        index += 32;

        transfer.toChain = encoded.toUint16(index);
        index += 2;

        length = encoded.toUint16(index);
        index += 2;

        transfer.data = encoded.slice(index, length);
        index += length;

        length = encoded.toUint16(index);
        index += 2;

        transfer.mintData = encoded.slice(index, length);
        index += length;

        //require(encoded.length == index, "invalid Transfer");
    }

    // Governance
     // "NFTBridge" (left padded)
    bytes32 constant module = 0x00000000000000000000000000000000000000000000004e4654427269646765;

    // function parseRegisterChain(bytes memory encoded) external pure override returns(CommonStructs.RegisterChain memory chain) {
    //     uint index = 0;

    //     // governance header

    //     chain.module = encoded.toBytes32(index);
    //     index += 32;
    //     require(chain.module == module, "invalid RegisterChain: wrong module");

    //     chain.action = encoded.toUint8(index);
    //     index += 1;
    //     require(chain.action == 1, "invalid RegisterChain: wrong action");

    //     chain.chainId = encoded.toUint16(index);
    //     index += 2;

    //     // payload

    //     chain.emitterChainID = encoded.toUint16(index);
    //     index += 2;

    //     chain.emitterAddress = encoded.toBytes32(index);
    //     index += 32;

    //     require(encoded.length == index, "invalid RegisterChain: wrong length");
    // }

    // function parseUpgrade(bytes memory encoded) external pure override returns(CommonStructs.UpgradeContract memory chain) {
    //     uint index = 0;

    //     // governance header
    //     chain.module = encoded.toBytes32(index);
    //     index += 32;
    //     require(chain.module == module, "invalid UpgradeContract: wrong module");

    //     chain.action = encoded.toUint8(index);
    //     index += 1;
    //     require(chain.action == 2, "invalid UpgradeContract: wrong action");

    //     chain.chainId = encoded.toUint16(index);
    //     index += 2;

    //     // payload

    //     chain.newContract = encoded.toBytes32(index);
    //     index += 32;

    //     require(encoded.length == index, "invalid UpgradeContract: wrong length");
    // }

    function createWrapped(CommonStructs.Transfer memory transfer, CommonStructs.NFTInitArgs memory initArgs, address beacon721Addr, address beacon1155Addr, address standardBeaconAddr, address bridgeAddr) external override returns (uint16, bytes32, address) {
        require(transfer.tokenType == 2 || transfer.tokenType == 1, "Token Type can only be 1 or 2, which stands for ERC721 or ERC1155");
        require(transfer.tokenAddress != bytes32(0), "native NFT address canonot be 0 address");
        require(bridgeAddr != address(0), "Bridge Address cannot be 0 address");

        address token;
        WrappedNFTAssetArgs memory wrappedNFTAssetArgs;
        wrappedNFTAssetArgs.tokenAddress = transfer.tokenAddress;
        wrappedNFTAssetArgs.collectionOwner = transfer.collectionOwner;
        wrappedNFTAssetArgs.tokenChain = transfer.tokenChain;
        wrappedNFTAssetArgs.royaltyInfo.royaltyAddress = address(
            uint160(uint256(transfer.royaltyAddress))
        );
        wrappedNFTAssetArgs.royaltyInfo.royaltyBips = transfer.royaltyBips;
        wrappedNFTAssetArgs.standardID = transfer.standardID;
        wrappedNFTAssetArgs.data = transfer.data;

        // SPL NFTs all use the same NFT contract, so unify the name
        if (transfer.tokenChain == 1) {
            // "Messina Bridged Solana-NFT" - right-padded
            transfer.name = 0x4d657373696e61204272696467656420536f6c616e612d4e4654000000000000;
            // "MESSINASPLNFT" - right-padded
            transfer.symbol = 0x4d455353494e4153504c4e465400000000000000000000000000000000000000;
        }

        bytes memory bytecode;
        if (wrappedNFTAssetArgs.standardID == 0) {
            // if standardID 0 means is non-messina or messina standrd which will use the default 721 or 1155 beacon
            if (transfer.tokenType == 2) {
                wrappedNFTAssetArgs.beaconAddr = beacon1155Addr;
                wrappedNFTAssetArgs.selectorBytes = NFT1155Implementation
                    .initialize
                    .selector;
            } else {
                wrappedNFTAssetArgs.beaconAddr = beacon721Addr;
                wrappedNFTAssetArgs.selectorBytes = NFTImplementation
                    .initialize
                    .selector;
            }
        } else {
            // else if standardID not 0, means its other NFTImplementation and have their own beacon
            wrappedNFTAssetArgs.beaconAddr = standardBeaconAddr;
            wrappedNFTAssetArgs.selectorBytes = initArgs.selectorBytes;
            wrappedNFTAssetArgs.data = initArgs.data;
        }

        require(
            wrappedNFTAssetArgs.beaconAddr != address(0),
            "Beacon Address cannot be 0 address (already setNFTBeaconAddress for this standardID?)"
        );
        
        // TokenType 2 is 1155, 1 is 721
        if (transfer.tokenType == 2) {
            // initialize the NFT1155Implementation
            wrappedNFTAssetArgs.initialisationArgs = abi.encodeWithSelector(
                wrappedNFTAssetArgs.selectorBytes,
                transfer.uri,
                wrappedNFTAssetArgs.collectionOwner,
                bridgeAddr,
                wrappedNFTAssetArgs.tokenChain,
                wrappedNFTAssetArgs.tokenAddress,
                wrappedNFTAssetArgs.royaltyInfo.royaltyAddress,
                wrappedNFTAssetArgs.royaltyInfo.royaltyBips,
                wrappedNFTAssetArgs.standardID,
                wrappedNFTAssetArgs.data
            );
        } else {
            // initialize the NFTImplementation
            wrappedNFTAssetArgs.initialisationArgs = abi.encodeWithSelector(
                wrappedNFTAssetArgs.selectorBytes,
                transfer.name.bytes32ToString(),
                transfer.symbol.bytes32ToString(),
                wrappedNFTAssetArgs.collectionOwner,
                bridgeAddr,
                wrappedNFTAssetArgs.tokenChain,
                wrappedNFTAssetArgs.tokenAddress,
                wrappedNFTAssetArgs.royaltyInfo.royaltyAddress,
                wrappedNFTAssetArgs.royaltyInfo.royaltyBips,
                wrappedNFTAssetArgs.standardID,
                wrappedNFTAssetArgs.data
            );
        }

        // initialize the BeaconProxy
        wrappedNFTAssetArgs.constructorArgs = abi.encode(
            wrappedNFTAssetArgs.beaconAddr,
            wrappedNFTAssetArgs.initialisationArgs
        );

        // deployment code
        bytecode = abi.encodePacked(
            type(BridgeNFT).creationCode,
            wrappedNFTAssetArgs.constructorArgs
        );

        bytes32 salt = keccak256(
            abi.encodePacked(
                wrappedNFTAssetArgs.tokenChain,
                wrappedNFTAssetArgs.tokenAddress
            )
        );

        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            if iszero(extcodesize(token)) {
                revert(0, 0)
            }
        }

        return (
            wrappedNFTAssetArgs.tokenChain,
            wrappedNFTAssetArgs.tokenAddress,
            token
        );
    }
}
