// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../Structs.sol";
import "../interfaces/IWormhole.sol";

contract RouterImplementation is Initializable, ERC1967Upgrade, OwnableUpgradeable, ReentrancyGuard {
    using Strings for uint32;
    using Strings for uint8;

    event RouterLogMessagePublished(string network, address indexed sender, uint32 nonce, bytes payload, uint8 consistencyLevel);

    event NewNftBridgeAddress(
        address indexed prevNftBridge,
        address indexed newNftBridge
    );

    event NewNetworkAddressAdded(string network, address indexed newNetworkAddress);

    mapping(string => address) public networkAddress;
    address public bridgeAddress;

    function initialize() public initializer {
        __Ownable_init();
    }

    function publishMessage(
        string memory network,
        uint256 callValue,
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) public payable nonReentrant {
        require(msg.sender == bridgeAddress, "msg.sender is not a valid bridgeAddress");

        emit RouterLogMessagePublished(network, msg.sender, nonce, payload, consistencyLevel);

        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("MESSINA_WORMHOLE"))) {
            address messinaNetworkAddr = networkAddress["MESSINA"];
            address wormholeNetworkAddr = networkAddress["WORMHOLE"];

            // No need to return wormhole sequence
            publishInnerMessage(wormholeNetworkAddr, payload, nonce, consistencyLevel, IWormhole(wormholeNetworkAddr).messageFee());

            publishInnerMessage(messinaNetworkAddr, payload, nonce, consistencyLevel, IWormhole(messinaNetworkAddr).messageFee());
        } else {
            address networkAddr = networkAddress[network];
            publishInnerMessage(networkAddr, payload, nonce, consistencyLevel, callValue);
        }
    }

    function publishInnerMessage(address network, bytes memory payload, uint32 nonce, uint8 consistencyLevel, uint256 callValue) private returns (uint64) {
        require(network != address(0), "Router: core contract address cannot be 0 address");
        return IWormhole(network).publishMessage{value : callValue}(nonce, payload, consistencyLevel);
    }

    function parseAndVerifyVM (
        string memory network,
        bytes calldata encodedVM
    ) external view returns (Structs.VM memory routerVm, bool routerValid, string memory routerReason) {
        require(msg.sender == bridgeAddress, "msg.sender is not a valid bridgeAddress");

        address networkAddr = networkAddress[network];
        require(networkAddr != address(0), "Router: core contract address cannot be 0 address");

       (routerVm, routerValid, routerReason) = IWormhole(networkAddr).parseAndVerifyVM(encodedVM);
    }

    function addNetworkAddress(string memory network, address networkAddr) external onlyOwner {
        require(networkAddr != address(0), "Router: core contract address cannot be 0 address");
        networkAddress[network] = networkAddr;

        emit NewNetworkAddressAdded(network, networkAddr);
    }

    function getNetworkAddress(string memory network) external view returns (address) {
        return networkAddress[network];
    }

    function getBridgeAddress() external view returns (address) {
        return bridgeAddress;
    }

    function setBridgeAddress(address newBridgeAddress) external onlyOwner {
        require(newBridgeAddress != address(0), "Router: bridge address cannot be 0 address");
        address oldBridgeAddress = bridgeAddress;
        bridgeAddress = newBridgeAddress;
        
        emit NewNftBridgeAddress(oldBridgeAddress, newBridgeAddress);
    }

    function messageFee(string memory network) external view returns (uint256) {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("MESSINA_WORMHOLE"))) {
            address messinaNetworkAddr = networkAddress["MESSINA"];
            address wormholeNetworkAddr = networkAddress["WORMHOLE"];
            require(wormholeNetworkAddr != address(0) || messinaNetworkAddr != address(0), "Router: core contract address cannot be 0 address");

            return IWormhole(wormholeNetworkAddr).messageFee() + IWormhole(messinaNetworkAddr).messageFee();
        }

        address networkAddr = networkAddress[network];
        require(networkAddr != address(0), "Router: core contract address cannot be 0 address");
        return IWormhole(networkAddr).messageFee();
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _upgradeTo(newImplementation);
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}