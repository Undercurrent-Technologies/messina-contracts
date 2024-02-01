// contracts/MockNFTImplementation721.sol
// SPDX-License-Identifier: Apache 2

// This is a Mock NFT for testing NFTImplementation upgrade

pragma solidity ^0.8.0;

import "../token/NFTImplementation.sol";

contract MockNFT721Implementation is NFTImplementation {
    function testNewImplementationActive() external pure returns (bool) {
        return true;
    }
}
