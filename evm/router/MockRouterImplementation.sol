// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../Structs.sol";
import "../interfaces/IMessinaRouter.sol";
import "./RouterImplementation.sol";

contract MockRouterImplementation is RouterImplementation {

    function proveUpgradedw42() external pure returns (uint) {
        return 42;
    }
}