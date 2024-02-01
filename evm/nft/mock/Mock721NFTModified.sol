// contracts/Mock721NFTModified.sol
// SPDX-License-Identifier: Apache 2

// This is a Messina 721 MockNFT + ERC721Enumerable

pragma solidity ^0.8.0;

import "../token/Messina721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract Mock721NFTModified is Messina721, IERC721Enumerable {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address nftBridge_,
        uint16 chainId_,
        bytes32 nativeContract_,
        address royaltyReceiver_,
        uint96 royaltyFeesInBips_,
        uint16 standardID_,
        bytes memory data_
    )
        Messina721(
            name_,
            symbol_,
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

    // (User Mint) simple example of mint function for User
    function mint(
        address to,
        uint256 tokenId,
        string memory uri,
        bytes memory data
    ) public {
        _safeMint(to, tokenId, uri, data);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, Messina721) returns (bool) {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) public view virtual override returns (uint256) {
        require(
            index < Messina721.balanceOf(owner),
            "ERC721Enumerable: owner index out of bounds"
        );
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(
        uint256 index
    ) public view virtual override returns (uint256) {
        require(
            index < totalSupply(),
            "ERC721Enumerable: global index out of bounds"
        );
        return _allTokens[index];
    }

    function setChainId(uint16 _chainId) public virtual onlyOwner {
        state.chainId = _chainId;
    }

    function setNativeContract(bytes32 _nativeContract) public virtual onlyOwner {
        state.nativeContract = _nativeContract;
    }
}
