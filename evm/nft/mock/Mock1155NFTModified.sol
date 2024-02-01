// contracts/Mock1155NFTModified.sol
// SPDX-License-Identifier: Apache 2

// This is a Messina 1155 MockNFT + ERC1155Supply Implementation of Openzeppelin

pragma solidity ^0.8.0;

import "../1155token/Messina1155.sol";

contract Mock1155NFTModified is Messina1155 {
    mapping(uint256 => uint256) private _totalSupply;

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
    )
        Messina1155(
            uri_,
            owner_,
            nftBridge_,
            chainId_,
            nativeContract_,
            royaltyReceiver_,
            royaltyFeesInBips_,
            standardID_,
            data_
        )
    {}

    function setURI(string memory newuri) public virtual onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public {
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

    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) public view virtual returns (bool) {
        return totalSupply(id) > 0;
    }

    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                _totalSupply[ids[i]] += amounts[i];
            }
        }

        if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                uint256 id = ids[i];
                uint256 amount = amounts[i];
                uint256 supply = _totalSupply[id];
                require(
                    supply >= amount,
                    "ERC1155: burn amount exceeds totalSupply"
                );
                unchecked {
                    _totalSupply[id] = supply - amount;
                }
            }
        }
    }

    function setChainId(uint16 _chainId) public virtual onlyOwner {
        state.chainId = _chainId;
    }

    function setNativeContract(bytes32 _nativeContract) public virtual onlyOwner {
        state.nativeContract = _nativeContract;
    }
}
