// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./NFTBridgeStructs.sol";
import "../libraries/external/CommonStructs.sol";

contract NFTBridgeStorage {
    struct Provider {
        uint16 chainId;
        // Required number of block confirmations to assume finality
        uint8 finality;
    }

    struct Asset {
        uint16 chainId;
        bytes32 assetAddress;
    }

    struct SPLCache {
        bytes32 name;
        bytes32 symbol;
    }

    struct State {
        address payable wormhole;
        address owner;
        address helperAddr;
        address royaltyRegistryAddr;
        // address tokenImplementation;
        address messina721Beacon;
        // address token1155Implementation;
        address messina1155Beacon;
        address treasuryAddr;
        address payable routerAddr;
        uint256 fee;
        bool paused;
        Provider provider;

        // Mapping of consumed governance actions
        mapping(bytes32 => bool) consumedGovernanceActions;

        // Mapping of consumed token transfers
        mapping(bytes32 => bool) completedTransfers;

        // Mapping of initialized implementations
        mapping(address => bool) initializedImplementations;

        // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
        mapping(uint16 => mapping(bytes32 => address)) wrappedAssets;

        // Mapping to safely identify wrapped assets
        mapping(address => bool) isWrappedAsset;

        // Mapping of bridge contracts on other chains
        mapping(uint16 => bytes32) bridgeImplementations;

        // Mapping of spl token info caches (chainID => nativeAddress => SPLCache)
        mapping(uint256 => SPLCache) splCache;

        // Mapping of NFTType to Beacon Address
        mapping(uint16 => address) nftBeacon;

        // Mapping of NFTType's to its Args when initialize
        mapping(uint16 => CommonStructs.NFTInitArgs) nftInitArgs;

    }
}

contract NFTBridgeState {
    NFTBridgeStorage.State internal state;

    mapping(address => bool) internal isCollectionBlacklisted;
}