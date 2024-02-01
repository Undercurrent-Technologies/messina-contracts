// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IMessina1155 {

    event NewNftBridgeAddress(
        address indexed prevNftBridge,
        address indexed newNftBridge
    );

    function getChainId() external view returns (uint16);

    function getNativeContract() external view returns (bytes32);

    function getChainIdNNativeContract() external view returns (uint16, bytes32);

    function getOwner() external view returns (address);

    function getNFTBridge() external view returns (address);

    function getCreateData() external view returns (bytes memory);

    function getStandardID() external view returns (uint16);

    function getCreateDataNStandardID() external view returns (bytes memory, uint16);

    function setNFTBridge(address newNftBridge) external;

    function bridgeMint(address to, uint256 id, uint256 amount, bytes memory data) external;
    
    function bridgeMintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;
    
    function bridgeBurn(address from, uint256 tokenId, uint256 amount) external;
    
    function bridgeBurnBatch(address from, uint256[] memory ids, uint256[] memory amounts) external;
}