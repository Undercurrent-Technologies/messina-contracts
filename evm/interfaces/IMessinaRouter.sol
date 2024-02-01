// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Structs.sol";

interface IMessinaRouter {
    function publishMessage(
        string memory network,
        uint256 callValue,
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable;

    function parseAndVerifyVM(string memory network, bytes calldata encodedVM) external view returns (Structs.VM memory vm, bool valid, string memory reason);

    function messageFee(string memory _network) external view returns (uint256);
}