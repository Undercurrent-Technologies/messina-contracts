// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IMessina721 {

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

    function getMintData(uint256 tokenId) external view returns (bytes memory);

    function setNFTBridge(address newNftBridge) external;

    function bridgeMint(address to, uint256 tokenId, string memory uri, bytes memory data) external;

    function bridgeBurn(uint256 tokenId) external;
}