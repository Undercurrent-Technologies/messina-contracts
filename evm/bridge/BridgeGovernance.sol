// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../libraries/external/BytesLib.sol";

import "./BridgeGetters.sol";
import "./BridgeSetters.sol";
import "./BridgeStructs.sol";

import "./token/Token.sol";
import "./token/TokenImplementation.sol";

import "../interfaces/IWormhole.sol";

contract BridgeGovernance is BridgeGetters, BridgeSetters, ERC1967Upgrade {
    using BytesLib for bytes;
    using Address for address;

    // "TokenBridge" (left padded)
    bytes32 constant module = 0x000000000000000000000000000000000000000000546f6b656e427269646765;

    // The foreignBridgeAddress variable is in the bytes32 format, which means that it is a 32-byte address that has been left-padded with zeros.    function registerChain(uint16 foreignChainID, bytes32 foreignBridgeAddress) public onlyOwner {
    function registerChain(uint16 foreignChainID, bytes32 foreignBridgeAddress) public onlyOwner {
        require(foreignBridgeAddress != bytes32(0), "foreign bridge address cannot be 0 address");
        setBridgeImplementation(foreignChainID, foreignBridgeAddress);
    }
    
    function upgrade(address newContract) public onlyOwner {
        require(newContract != address(0), "new implementation bridge address cannot be 0 address");
        require(newContract.isContract(), "new implementation bridge address needs to be a contract address");
        upgradeImplementation(newContract);
    }

    event ContractUpgraded(address indexed oldContract, address indexed newContract);

    function upgradeImplementation(address newImplementation) internal {
        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // Call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }

}