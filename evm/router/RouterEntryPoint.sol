// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RouterEntryPoint is ERC1967Proxy {
    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) {
    }
}
