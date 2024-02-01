// contracts/Implementation.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "./NFTBridge.sol";
import "./token/NFTBeacon.sol";

contract NFTBridgeImplementation is NFTBridge {
    // nftType of 1 is 721, 2 is 1155
    function updateNFTBeaconImpl(uint8 nftType, uint8 standardID, address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "invalid implementation address");
        address beaconAddr;
        if (standardID == 0) {
            if (nftType == 2) {
                beaconAddr = state.messina1155Beacon;
            } else {
                beaconAddr = state.messina721Beacon;
            }
        } else {
            beaconAddr = state.nftBeacon[standardID];
        }
        NFTBeacon(beaconAddr).update(newImplementation);
    }

    function initialize() public virtual initializer {
        // this function needs to be exposed for an upgrade to pass
    }

    modifier initializer() {
        address impl = ERC1967Upgrade._getImplementation();

        require(!isInitialized(impl), "already initialized");

        setInitialized(impl);

        _;
    }
}
