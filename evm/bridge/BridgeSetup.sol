// contracts/BridgeSetup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./BridgeGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract BridgeSetup is BridgeSetters, ERC1967Upgrade {
    bool initialized = false;

    function setup(
        address implementation,
        uint16 chainId,
        address WETH,
        uint8 finality,
        address routerAddress
    ) public {
        require(!initialized, "already initialized");
        require(implementation != address(0), "implementation address cannot be 0 address");
        require(routerAddress != address(0), "routerAddress address cannot be 0 address");
        require(WETH != address(0), "WETH address cannot be 0 address");

        setChainId(chainId);

        setWETH(WETH);

        _state.owner = msg.sender;
        _state.treasury = msg.sender;
        _state.provider.finality = finality;

        _upgradeTo(implementation);

        _state.routerAddr = payable(routerAddress);

        initialized = true;
    }
}
