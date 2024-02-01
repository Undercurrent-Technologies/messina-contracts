// contracts/BridgeSetup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./token/NFTBeacon.sol";
import "./NFTBridgeGovernance.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract NFTBridgeSetup is NFTBridgeSetters, ERC1967Upgrade {
    NFTBeacon private beacon1155;
    NFTBeacon private beacon721;

    function setup(
        address implementation,
        uint16 chainId,
        address owner,
        address helperAddr,
        address royaltyRegistryAddr,
        address tokenImplementation,
        address token1155Implementation,
        uint8 finality,
        address routerAddress,
        uint256 fee
    ) public {
        require(implementation != address(0), "implementation address cannot be 0 address");
        require(owner != address(0), "owner address cannot be 0 address");
        require(helperAddr != address(0), "helper address cannot be 0 address");
        require(royaltyRegistryAddr != address(0), "royaltyRegistry address cannot be 0 address");
        require(tokenImplementation != address(0), "tokenImplementation address cannot be 0 address");
        require(token1155Implementation != address(0), "token1155Implementation address cannot be 0 address");
        require(routerAddress != address(0), "routerAddress address cannot be 0 address");

        setChainId(chainId);

        // setTokenImplementation(tokenImplementation);
        beacon721 = new NFTBeacon(tokenImplementation, msg.sender);
        // set721Beacon(address(beacon721));
        state.messina721Beacon = address(beacon721);

        // setToken1155Implementation(token1155Implementation);
        beacon1155 = new NFTBeacon(token1155Implementation, msg.sender);
        // set1155Beacon(address(beacon1155));
        state.messina1155Beacon = address(beacon1155);

        // These are onlyOwner functions
        state.royaltyRegistryAddr = royaltyRegistryAddr;
        state.helperAddr = helperAddr;
        state.owner = owner;
        state.provider.finality = finality;
        state.treasuryAddr = msg.sender;
        state.fee = fee;
        state.routerAddr = payable(routerAddress);

        _upgradeTo(implementation);
    }
}
