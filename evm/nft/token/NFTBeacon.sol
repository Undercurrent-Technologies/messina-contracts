// contracts/NFTBeacon.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

contract NFTBeacon is IBeacon {
    UpgradeableBeacon immutable private beacon;

    address public implementationAddr;
    address public admin;
    address public nftBridge;

    event NewNftBridgeAddress(
        address indexed prevNftBridge,
        address indexed newNftBridge
    );

    event AdminChanged(
        address indexed oldAdmin,
        address indexed newAdmin
    );

    constructor(address implementationAddr_, address admin_) {
        require(implementationAddr_ != address(0), "implementationAddr_ is a zero address");
        require(admin_ != address(0), "admin_ a zero address");
        implementationAddr = implementationAddr_;
        admin = admin_;
        beacon = new UpgradeableBeacon(implementationAddr_);
    }

    function update(address newImplementationAddr) public onlyNFTBridgeORAdmin {
        require(newImplementationAddr != address(0), "its a zero address");
        implementationAddr = newImplementationAddr;
        beacon.upgradeTo(newImplementationAddr);
    }

    function implementation() public view override returns (address) {
        return beacon.implementation();
    }

    function setNFTBridge(address newNFTBridge) public onlyAdmin {
        require(newNFTBridge != address(0), "new NFTBridge cannot be a zero address");
        address oldNFTBridge = newNFTBridge;
        nftBridge = newNFTBridge;
        emit NewNftBridgeAddress(oldNFTBridge, newNFTBridge);
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "its zero address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "caller is not the admin");
        _;
    }

    modifier onlyNFTBridgeORAdmin() {
        require(
            nftBridge == msg.sender || admin == msg.sender,
            "caller is not the NFTBridge nor admin"
        );
        _;
    }
}