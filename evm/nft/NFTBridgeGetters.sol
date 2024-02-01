// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./NFTBridgeState.sol";
import "../libraries/external/CommonStructs.sol";
import "../interfaces/IMessinaRouter.sol";

contract NFTBridgeGetters is NFTBridgeState {
    function isInitialized(address impl) public view returns (bool) {
        return state.initializedImplementations[impl];
    }

    function isTransferCompleted(bytes32 hash) public view returns (bool) {
        return state.completedTransfers[hash];
    }

    function chainId() public view returns (uint16){
        return state.provider.chainId;
    }

    function finality() public view returns (uint8) {
        return state.provider.finality;
    }

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view returns (address){
        return state.wrappedAssets[tokenChainId][tokenAddress];
    }

    function bridgeContracts(uint16 chainId_) public view returns (bytes32){
        return state.bridgeImplementations[chainId_];
    }

    // function tokenImplementation() public view returns (address){
    //     return state.tokenImplementation;
    // }

    function messina721Beacon() public view returns (address){
        return state.messina721Beacon;
    }

    // function token1155Implementation() public view returns (address){
    //     return state.token1155Implementation;
    // }

    function messina1155Beacon() public view returns (address){
        return state.messina1155Beacon;
    }

    function isWrappedAsset(address token) public view returns (bool){
        return state.isWrappedAsset[token];
    }

    function splCache(uint256 tokenId) public view returns (NFTBridgeStorage.SPLCache memory) {
        return state.splCache[tokenId];
    }

    function getNFTInitArgs(
        uint16 standardId
    ) public view returns (CommonStructs.NFTInitArgs memory) {
        return state.nftInitArgs[standardId];
    }

    function getNFTBeacon(uint16 standardId) public view returns (address) {
        return state.nftBeacon[standardId];
    }

    function getHelperAddr() public view returns (address){
        return state.helperAddr;
    }

    function getRoyaltyRegistryAddr() public view returns (address){
        return state.royaltyRegistryAddr;
    }

    function getOwner() public view returns (address){
        return state.owner;
    }

    function getTreasuryAddr() public view returns (address){
        return state.treasuryAddr;
    }

    function getFee() public view returns (uint256){
        return state.fee;
    }

    function getRouterAddr() public view returns (address){
        return state.routerAddr;
    }

    function router() public view returns (IMessinaRouter){
        return IMessinaRouter(state.routerAddr);
    }

    function isPaused() public view returns (bool) {
        return state.paused;
    }

    function isCollectionAddressBlacklisted(address token) public view returns (bool){
        return isCollectionBlacklisted[token];
    }
}
