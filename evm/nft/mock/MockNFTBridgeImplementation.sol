// contracts/MockNFTBridgeImplementation.sol
// SPDX-License-Identifier: Apache 2

// This is a Mock NFT for testing bridge upgrade

pragma solidity ^0.8.0;

import "../NFTBridgeImplementation.sol";

contract MockNFTBridgeImplementation is NFTBridgeImplementation {
    function initialize() initializer public override {
        // this function needs to be exposed for an upgrade to pass
    }

    function testNewImplementationActive() external pure returns (bool) {
        return true;
    }
}
