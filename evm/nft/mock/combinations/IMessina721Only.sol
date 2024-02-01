// contracts/Messina721.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../../../interfaces/IERC4907.sol";
import "../../../interfaces/IMessina721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../../../libraries/external/BytesLib.sol";

// Based on the OpenZepplin ERC721 implementation, licensed under MIT
contract Messina721Only is
    Context,
    IERC721,
    IERC721Metadata,
    ERC165,
    IMessina721
{
    struct UserInfo {
        address user; // address of user role
        uint64 expires; // unix timestamp, user expires
    }

    struct CreateData {
        address testAddress;
        uint256 amount;
        uint256[] array;
        string uri;
    }

    struct MintData {
        address testAddress;
        uint256 amount;
    }

    struct State {
        // Token name
        string name;
        // Token symbol
        string symbol;
        // Mapping from token ID to owner address
        mapping(uint256 => address) owners;
        // Mapping owner address to token count
        mapping(address => uint256) balances;
        // Mapping from token ID to approved address
        mapping(uint256 => address) tokenApprovals;
        // Mapping from token ID to URI
        mapping(uint256 => string) tokenURIs;
        // Mapping from owner to operator approvals
        mapping(address => mapping(address => bool)) operatorApprovals;
        // Mapping from tokenID to createData
        mapping(uint256 => bytes) tokenData;

        address owner;
        address nftBridge;
        bool initialized;
        uint16 chainId;
        uint16 standardID;
        bytes32 nativeContract;
        bytes data;
    }

    State internal _state;
    // Mapping for users of ERC4907
    mapping(uint256 => UserInfo) internal _users;

    using Address for address;
    using Strings for uint256;

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
    ) {
        _state.name = name_;
        _state.symbol = symbol_;
        _state.owner = owner_;
        _state.nftBridge = nftBridge_;
        _state.chainId = chainId_;
        _state.nativeContract = bytes32(uint256(uint160(address(this))));
        abi.encode(royaltyReceiver_, royaltyFeesInBips_, nativeContract_);
        _state.standardID = standardID_;
        _state.data = data_;
    }

    // (User Mint) simple example of mint function for User
    function mint(
        address to,
        uint256 tokenId,
        string memory uri,
        bytes memory data
    ) public {
        _safeMint(to, tokenId, uri, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IMessina721).interfaceId ||
            // interfaceId == type(IERC4907).interfaceId ||
            // interfaceId == type(ERC2981).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner_) public view virtual override returns (uint256) {
        require(owner_ != address(0), "ERC721: balance query for the zero address");
        return _state.balances[owner_];
    }

    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner_ = _state.owners[tokenId];
        require(owner_ != address(0), "ERC721: owner query for nonexistent token");
        return owner_;
    }

    function name() public view virtual override returns (string memory) {
        return _state.name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _state.symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return _state.tokenURIs[tokenId];
    }

    function getChainId() public view virtual override returns (uint16) {
        return _state.chainId;
    }

    function getNativeContract() public view virtual override returns (bytes32) {
        return _state.nativeContract;
    }

    function setNativeContract(bytes32 _nativeContract) public virtual onlyOwner {
        _state.nativeContract = _nativeContract;
    }

    function getChainIdNNativeContract() public view virtual override returns (uint16, bytes32) {
        return (_state.chainId, _state.nativeContract);
    }

    function getOwner() public view virtual override returns (address) {
        return _state.owner;
    }

    function getNFTBridge() public view virtual override returns (address) {
        return _state.nftBridge;
    }

    function getCreateData() public view virtual override returns (bytes memory) {
        return _state.data;
    }

    function getMintData(uint256 tokenId) public view virtual override returns (bytes memory) {
        require(_exists(tokenId), "Messina721: invalid query for nonexistent token");

        return _state.tokenData[tokenId];
    }

    function getStandardID() public view virtual override returns (uint16) {
        return _state.standardID;
    }

    function getCreateDataNStandardID() public view virtual override returns (bytes memory, uint16) {
        return (_state.data, _state.standardID);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner_ = ownerOf(tokenId);
        require(to != owner_, "ERC721: approval to current owner");

        require(
            _msgSender() == owner_ || isApprovedForAll(owner_, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _state.tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
    {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _state.operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner_, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _state.operatorApprovals[owner_][operator];
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _state.owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner_, spender));
    }

    function _isApprovedOrOwnerOrNFTBridge(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ ||
            spender == getNFTBridge() ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner_, spender));
    }

    // (Bridge Mint) mint function of NFTBridge
    function bridgeMint(address to, uint256 tokenId, string memory uri, bytes memory data) public virtual override onlyNFTBridge {
        _safeMint(to, tokenId, uri, data);
    }
    
    function _safeMint(address to, uint256 tokenId, string memory uri) internal virtual {
        _safeMint(to, tokenId, uri, "");
    }

    function _safeMint(address to, uint256 tokenId, string memory uri, bytes memory data) internal virtual {
        _mint(to, tokenId, uri, data);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _mint(
        address to,
        uint256 tokenId,
        string memory uri,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        _beforeTokenTransfer(address(0), to, tokenId);

        require(!_exists(tokenId), "ERC721: token already minted");

        // Mint a new token
        _state.balances[to] += 1;
        _state.owners[tokenId] = to;
        _state.tokenURIs[tokenId] = uri;
        _state.tokenData[tokenId] = data;

        emit Transfer(address(0), to, tokenId);
    }

    function bridgeBurn(uint256 tokenId) public virtual override onlyNFTBridge {
        _burn(tokenId);
    }

    function _burn(uint256 tokenId) internal virtual {
        address owner_ = ownerOf(tokenId);

        _beforeTokenTransfer(owner_, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _state.balances[owner_] -= 1;
        delete _state.owners[tokenId];

        emit Transfer(owner_, address(0), tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(
            ownerOf(tokenId) == from,
            "ERC721: transfer of token that is not own"
        );
        require(to != address(0), "ERC721: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _beforeTokenTransfer(from, to, tokenId);

        _state.balances[from] -= 1;
        _state.balances[to] += 1;
        _state.owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _approve(address to, uint256 tokenId) internal virtual {
        _state.tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    _data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function setNFTBridge(address newNftBridge) public virtual override onlyOwner {
        require(newNftBridge != address(0), "new owner is the zero address");
        address oldNftBridge = _state.nftBridge;
        _state.nftBridge = newNftBridge;
        emit NewNftBridgeAddress(oldNftBridge, newNftBridge);
    }

    // // ERC2981 functions
    
    // function setRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips)
    //     public
    //     virtual
    //     onlyOwner
    // {
    //     _setDefaultRoyalty(_receiver, _royaltyFeesInBips);
    // }

    // // ERC4907 functions

    // /// @notice set the user and expires of an NFT
    // /// @dev The zero address indicates there is no user
    // /// Throws if `tokenId` is not valid NFT
    // /// @param user  The new user of the NFT
    // /// @param expires  UNIX timestamp, The new user could use the NFT before expires
    // function setUser(
    //     uint256 tokenId,
    //     address user,
    //     uint64 expires
    // ) public virtual override {
    //     require(
    //         _isApprovedOrOwnerOrNFTBridge(msg.sender, tokenId),
    //         "ERC4907: transfer caller is not owner nor approved"
    //     );
    //     UserInfo storage info = _users[tokenId];
    //     info.user = user;
    //     info.expires = expires;
    //     emit UpdateUser(tokenId, user, expires);
    // }

    // /// @notice Get the user address of an NFT
    // /// @dev The zero address indicates that there is no user or the user is expired
    // /// @param tokenId The NFT to get the user address for
    // /// @return The user address for this NFT
    // function userOf(uint256 tokenId)
    //     public
    //     view
    //     virtual
    //     override
    //     returns (address)
    // {
    //     if (uint256(_users[tokenId].expires) >= block.timestamp) {
    //         return _users[tokenId].user;
    //     } else {
    //         return address(0);
    //     }
    // }

    // /// @notice Get the user expires of an NFT
    // /// @dev The zero value indicates that there is no user
    // /// @param tokenId The NFT to get the user expires for
    // /// @return The user expires for this NFT
    // function userExpires(uint256 tokenId)
    //     public
    //     view
    //     virtual
    //     override
    //     returns (uint256)
    // {
    //     return _users[tokenId].expires;
    // }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        // if (from != to && _users[tokenId].user != address(0)) {
        //     delete _users[tokenId];
        //     emit UpdateUser(tokenId, address(0), 0);
        // }
    }

    // Modifier

    modifier onlyOwner() {
        require(getOwner() == _msgSender(), "caller is not the owner");
        _;
    }

    modifier onlyNFTBridge() {
        require(getNFTBridge() == _msgSender(), "caller is not the NFTBridge");
        _;
    }

    modifier initializer() {
        require(!_state.initialized, "Already initialized");

        _state.initialized = true;

        _;
    }
}
