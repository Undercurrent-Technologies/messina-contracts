// contracts/MockNFTImplementation1155.sol
// SPDX-License-Identifier: Apache 2

// This is a Mock NFT for testing NFTImplementation upgrade

pragma solidity ^0.8.0;

// import "../1155token/NFT1155Implementation.sol";
import "./MockNFTImplementation1155.sol";

contract MockNFT1155Implementation1 is MockNFT1155Implementation {
    function testNewSecondImplementationActive() external pure returns (bool) {
        return true;
    }
}
