// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./NFTBridgeState.sol";
import "../libraries/external/CommonStructs.sol";
import "../interfaces/IMessina721.sol";
import "../interfaces/IOwnable.sol";

contract NFTBridgeSetters is NFTBridgeState {
    function setInitialized(address implementatiom) internal {
        state.initializedImplementations[implementatiom] = true;
    }

    function setTransferCompleted(bytes32 hash) internal {
        state.completedTransfers[hash] = true;
    }

    function setChainId(uint16 chainId) internal {
        state.provider.chainId = chainId;
    }

    function setFinality(uint8 finality) external onlyOwner {
        state.provider.finality = finality;
    }

    function setBridgeImplementation(uint16 chainId, bytes32 bridgeContract) internal {
        state.bridgeImplementations[chainId] = bridgeContract;
    }

    // function setTokenImplementation(address impl) internal {
    //     state.tokenImplementation = impl;
    // }

    function set721Beacon(address beaconAddr) public onlyOwner{
        require(beaconAddr != address(0), "beacon address cannot be 0 address");
        state.messina721Beacon = beaconAddr;
    }

    // function setToken1155Implementation(address impl) internal {
    //     state.token1155Implementation = impl;
    // }

    function set1155Beacon(address beaconAddr) public onlyOwner {
        require(beaconAddr != address(0), "beaconAddr address cannot be 0 address");
        state.messina1155Beacon = beaconAddr;
    }

    function _setWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress, address wrapper) internal {
        state.wrappedAssets[tokenChainId][tokenAddress] = wrapper;
        state.isWrappedAsset[wrapper] = true;
    }

    function setWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress, address wrapper) external onlyOwner {
        require(wrapper != address(0), "wrapper address cannot be 0 address");
        require(tokenAddress != bytes32(0), "tokenAddress cannot be bytes32 0 address");

        address oldWrapper = state.wrappedAssets[tokenChainId][tokenAddress];
        if(state.wrappedAssets[tokenChainId][tokenAddress] != address(0)) {
            state.isWrappedAsset[oldWrapper] = false;
        }

        state.wrappedAssets[tokenChainId][tokenAddress] = wrapper;
        state.isWrappedAsset[wrapper] = true;
    }

    function setSplCache(uint256 tokenId, NFTBridgeStorage.SPLCache memory cache) internal {
        state.splCache[tokenId] = cache;
    }

    function clearSplCache(uint256 tokenId) internal {
        delete state.splCache[tokenId];
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "newOwner address cannot be 0 address");
        state.owner = newOwner;
    }

    function setNFTBeaconAddress(uint16 standardId, address nftBeaconAddr) external onlyOwner {
        require(nftBeaconAddr != address(0), "nftBeacon address cannot be 0 address");
        state.nftBeacon[standardId] = nftBeaconAddr;   
    }

    function setNFTInitArgs(uint16 standardId, CommonStructs.NFTInitArgs memory initArgs) external onlyOwner {
        state.nftInitArgs[standardId] = initArgs;
    }

    // TODO: Add in toUpgrade() when upgrading the bridge implementation (if there's space)
    function setHelperAddr(address newHelperAddr) external onlyOwner {
        require(newHelperAddr != address(0), "newHelperAddr address cannot be 0 address");
        state.helperAddr = newHelperAddr;
    }

    function setRoyaltyRegistryAddr(address newRoyaltyRegistryAddr) external onlyOwner {
        require(newRoyaltyRegistryAddr != address(0), "newRoyaltyRegistryAddr address cannot be 0 address");
        state.royaltyRegistryAddr = newRoyaltyRegistryAddr;
    }

    function setTreasuryAddr(address newTreasuryAddr) external onlyOwner {
        require(newTreasuryAddr != address(0), "newTreasuryAddr address cannot be 0 address");
        state.treasuryAddr = newTreasuryAddr;
    }
    
    function setFee(uint256 newFee) external onlyOwner {
        state.fee = newFee;
    }

    function setNFTBridgeForCollection(address collectionAddr, address newNFTBridgeAddr) external onlyOwner {
        require(collectionAddr != address(0) && newNFTBridgeAddr != address(0), "collectionAddr or newNFTBridgeAddr cannot be 0 address");
        IMessina721(collectionAddr).setNFTBridge(newNFTBridgeAddr);
    }

    function setNewOwnerForCollection(address collectionAddr, address newOwner) external onlyOwner {
        require(collectionAddr != address(0) && newOwner != address(0), "collectionAddr or newOwner cannot be 0 address");
        IOwnable(collectionAddr).transferOwnership(newOwner);
    }

    function setRouterAddr(address newRouterAddr) external onlyOwner {
        require(newRouterAddr != address(0), "router address cannot be 0 address");
        state.routerAddr = payable(newRouterAddr);
    }

    function pause() external onlyOwner {
        state.paused = true;
    }

    function unpause() external onlyOwner {
        state.paused = false;
    }

    function setCollectionAddressBlacklisted(address tokenAddress, bool isBlackisted) external onlyOwner {
        require(tokenAddress != address(0), "token address cannot be 0 address");
        isCollectionBlacklisted[tokenAddress] = isBlackisted;
    }

    modifier onlyOwner() {
        require(state.owner == msg.sender, "caller is not the owner");
        _;
    }
}
