// contracts/MockNFTImplementation721.sol
// SPDX-License-Identifier: Apache 2

// This is a Mock NFT for testing NFTImplementation upgrade

pragma solidity ^0.8.0;

// import "../token/NFTImplementation.sol";
import "./MockNFTImplementation721.sol";

contract MockNFT721Implementation1 is MockNFT721Implementation {
    function testNewSecondImplementationActive() external pure returns (bool) {
        return true;
    }
}
