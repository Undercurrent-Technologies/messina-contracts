// contracts/Mock1155NFT.sol
// SPDX-License-Identifier: Apache 2

// This is a MockNFT following the Messina1155 Standard

pragma solidity ^0.8.0;

import "../1155token/Messina1155.sol";

contract Mock1155NFT is Messina1155 {
    constructor(
        string memory uri_,
        address owner_,
        address nftBridge_,
        uint16 chainId_,
        bytes32 nativeContract_,
        address royaltyReceiver_,
        uint96 royaltyFeesInBips_,
        uint16 standardID_,
        bytes memory data_
    ) Messina1155(
        uri_,
        owner_,
        nftBridge_,
        chainId_,
        nativeContract_,
        royaltyReceiver_,
        royaltyFeesInBips_,
        standardID_,
        data_
    ){}

    function setURI(string memory newuri) public virtual onlyOwner {
        _setURI(newuri);
    }


    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public {
        _mintBatch(to, ids, amounts, data);
    }

    function setChainId(uint16 _chainId) public virtual onlyOwner {
        state.chainId = _chainId;
    }

    function setNativeContract(bytes32 _nativeContract) public virtual onlyOwner {
        state.nativeContract = _nativeContract;
    }
}
