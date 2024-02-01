// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./BridgeState.sol";
import "./BridgeStructs.sol";

contract BridgeSetters is BridgeState {
    function setInitialized(address implementatiom) internal {
        _state.initializedImplementations[implementatiom] = true;
    }

    function setTransferCompleted(bytes32 hash) internal {
        _state.completedTransfers[hash] = true;
    }

    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setBridgeImplementation(uint16 chainId, bytes32 bridgeContract)
        internal
    {
        _state.bridgeImplementations[chainId] = bridgeContract;
    }

    modifier onlyOwner() {
        require(_state.owner == msg.sender, "caller is not the owner");
        _;
    }

    function changeOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "_owner address cannot be 0 address");
        _state.owner = _owner;
    }

    function changeTreasury(address _treasury) external {
        require(_treasury != address(0), "_treasury cannot be 0 address");
        require(
            _state.treasury == msg.sender,
            "caller is not the current treasury"
        );
        _state.treasury = _treasury;
    }

    function pause() external onlyOwner {
        _state.paused = true;
    }

    function unpause() external onlyOwner {
        _state.paused = false;
    }

    function setRouterAddr(address newRouterAddr) external onlyOwner {
        require(newRouterAddr != address(0), "router address cannot be 0 address");
        _state.routerAddr = payable(newRouterAddr);
    }


    // function setTokenImplementation(address impl) internal {
    //     _state.tokenImplementation = impl;
    // }

    function setWETH(address weth) internal {
        _state.provider.WETH = weth;
    }

    function setWrappedAsset(
        uint16 tokenChainId,
        bytes32 tokenAddress,
        address wrapper
    ) internal {
        _state.wrappedAssets[tokenChainId][tokenAddress] = wrapper;
        _state.isWrappedAsset[wrapper] = true;
        _state.wrapperTracker[wrapper] = BridgeStructs.Asset(
            tokenChainId,
            tokenAddress
        );
    }

    function setFinality(uint8 finality) external onlyOwner {
        _state.provider.finality = finality;
    }

    function setTokenConfiguration(
        address tokenAddress,
        BridgeStructs.TokenConfig memory tokenConfig
    ) internal {
        _state.tokenConfigs[tokenAddress] = tokenConfig;
    }
}
