// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BridgeState.sol";
import "./BridgeStructs.sol";
import "../interfaces/IMessinaRouter.sol";

contract BridgeGetters is BridgeState {
    function isInitialized(address impl) public view returns (bool) {
        return _state.initializedImplementations[impl];
    }

    function isTransferCompleted(bytes32 hash) public view returns (bool) {
        return _state.completedTransfers[hash];
    }

    function chainId() public view returns (uint16){
        return _state.provider.chainId;
    }

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view returns (address){
        return _state.wrappedAssets[tokenChainId][tokenAddress];
    }

    function bridgeContracts(uint16 chainId_) public view returns (bytes32){
        return _state.bridgeImplementations[chainId_];
    }

    function WETH() public view returns (IWETH){
        return IWETH(_state.provider.WETH);
    }

    function getWETH() public view returns (address){
        return _state.provider.WETH;
    }

    function isWrappedAsset(address token) public view returns (bool){
        return _state.isWrappedAsset[token];
    }

    function finality() public view returns (uint8) {
        return _state.provider.finality;
    }

    function tokenConfig(address tokenAddress) public view returns (BridgeStructs.TokenConfig memory) {
        return _state.tokenConfigs[tokenAddress];
    }

    function getOwner() public view returns (address) {
        return _state.owner;
    }

    function getTreasury() public view returns (address) {
        return _state.treasury;
    }

    function isPaused() public view returns (bool) {
        return _state.paused;
    }

    function getRouterAddr() public view returns (address){
        return _state.routerAddr;
    }

    function Router() public view returns (IMessinaRouter){
        return IMessinaRouter(_state.routerAddr);
    }
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint amount) external;
}