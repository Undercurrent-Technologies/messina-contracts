// contracts/Bridge1155NFT.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract Bridge1155NFT is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {

    }
}