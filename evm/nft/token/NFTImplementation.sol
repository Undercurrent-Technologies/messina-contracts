// contracts/TokenImplementation.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./NFTState.sol";
import "../../interfaces/IERC4907.sol";
import "../../interfaces/IMessina721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../../libraries/external/BytesLib.sol";

// Based on the OpenZepplin ERC721 implementation, licensed under MIT
contract NFTImplementation is
    NFTState,
    Context,
    IERC721,
    IERC721Metadata,
    ERC165,
    ERC2981,
    IERC4907,
    IMessina721
{
    using Address for address;
    using Strings for uint256;

    function initialize(
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
    ) public initializer {
        state.name = name_;
        state.symbol = symbol_;
        state.owner = owner_;
        state.nftBridge = nftBridge_;
        state.chainId = chainId_;
        state.nativeContract = nativeContract_;
        if (royaltyReceiver_ != address(0)) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyFeesInBips_);
        }        
        state.standardID = standardID_;
        state.data = data_;
    }

   function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165, ERC2981)
        returns (bool)
    {
        return
            interfaceId == type(IMessina721).interfaceId || // Before we finalise our own interface
            interfaceId == type(IERC4907).interfaceId ||
            interfaceId == type(ERC2981).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner_) public view virtual override returns (uint256) {
        require(owner_ != address(0), "ERC721: balance query for the zero address");
        return state.balances[owner_];
    }

    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner_ = state.owners[tokenId];
        require(owner_ != address(0), "ERC721: owner query for nonexistent token");
        return owner_;
    }

    function name() public view virtual override returns (string memory) {
        return state.name;
    }

    function symbol() public view virtual override returns (string memory) {
        return state.symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return state.tokenURIs[tokenId];
    }

    function getChainId() public view virtual override returns (uint16) {
        return state.chainId;
    }

    function getNativeContract() public view virtual override returns (bytes32) {
        return state.nativeContract;
    }

    function getChainIdNNativeContract() public view virtual override returns (uint16, bytes32) {
        return (state.chainId, state.nativeContract);
    }

    function getOwner() public view virtual override returns (address) {
        return state.owner;
    }

    function getNFTBridge() public view virtual override returns (address) {
        return state.nftBridge;
    }

    function getCreateData() public view virtual override returns (bytes memory) {
        return state.data;
    }

    function getMintData(uint256 tokenId) public view virtual override returns (bytes memory) {
        require(_exists(tokenId), "Messina721: invalid query for nonexistent token");

        return state.tokenData[tokenId];
    }

    function getStandardID() public view virtual override returns (uint16) {
        return state.standardID;
    }

    function getCreateDataNStandardID() public view virtual override returns (bytes memory, uint16) {
        return (state.data, state.standardID);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner_ = NFTImplementation.ownerOf(tokenId);
        require(to != owner_, "ERC721: approval to current owner");

        require(
            _msgSender() == owner_ || isApprovedForAll(owner_, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return state.tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        state.operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner_, address operator) public view virtual override returns (bool) {
        return state.operatorApprovals[owner_][operator];
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

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
        bytes memory data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return state.owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner_ = NFTImplementation.ownerOf(tokenId);
        return (spender == owner_ || getApproved(tokenId) == spender || isApprovedForAll(owner_, spender));
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
        address owner_ = NFTImplementation.ownerOf(tokenId);
        return (spender == owner_ ||
            spender == getNFTBridge() ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner_, spender));
    }

    // (Bridge Mint) mint function of NFTBridge
    function bridgeMint(address to, uint256 tokenId, string memory uri, bytes memory data) public virtual override onlyNFTBridge {
        _safeMint(to, tokenId, uri, data);
    }

    function _safeMint(address to, uint256 tokenId, string memory uri, bytes memory data) internal virtual {
        _mint(to, tokenId, uri, data);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _mint(address to, uint256 tokenId, string memory uri, bytes memory data) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        _beforeTokenTransfer(address(0), to, tokenId);

        require(!_exists(tokenId), "ERC721: token already minted");

        // Mint a new token
        state.balances[to] += 1;
        state.owners[tokenId] = to;
        state.tokenURIs[tokenId] = uri;
        state.tokenData[tokenId] = data;

        emit Transfer(address(0), to, tokenId);
    }

    function bridgeBurn(uint256 tokenId) public virtual override onlyNFTBridge {
        _burn(tokenId);
    }

    function _burn(uint256 tokenId) internal virtual {
        address owner_ = NFTImplementation.ownerOf(tokenId);

        _beforeTokenTransfer(owner_, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        state.balances[owner_] -= 1;
        delete state.owners[tokenId];

        emit Transfer(owner_, address(0), tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(NFTImplementation.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _beforeTokenTransfer(from, to, tokenId);

        state.balances[from] -= 1;
        state.balances[to] += 1;
        state.owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _approve(address to, uint256 tokenId) internal virtual {
        state.tokenApprovals[tokenId] = to;
        emit Approval(NFTImplementation.ownerOf(tokenId), to, tokenId);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
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

    function setNFTBridge(address newNftBridge) public virtual override onlyNFTBridge {
        require(newNftBridge != address(0), "its zero address");
        address oldNftBridge = state.nftBridge;
        state.nftBridge = newNftBridge;
        emit NewNftBridgeAddress(oldNftBridge, newNftBridge);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "its zero address");
        state.owner = newOwner;
    }

    // ERC2981 functions
    
    function setRoyaltyInfo(address receiver, uint96 royaltyFeesInBips)
        public
        virtual
        onlyOwner
    {
        _setDefaultRoyalty(receiver, royaltyFeesInBips);
    }

    // ERC4907 functions

    /// @notice set the user and expires of an NFT
    /// @dev The zero address indicates there is no user
    /// Throws if `tokenId` is not valid NFT
    /// @param user  The new user of the NFT
    /// @param expires  UNIX timestamp, The new user could use the NFT before expires
    function setUser(
        uint256 tokenId,
        address user,
        uint64 expires
    ) public virtual override {
        require(
            _isApprovedOrOwnerOrNFTBridge(msg.sender, tokenId),
            "ERC4907: transfer caller is not owner nor approved"
        );
        NFTStorage.UserInfo storage info = users[tokenId];
        info.user = user;
        info.expires = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    /// @notice Get the user address of an NFT
    /// @dev The zero address indicates that there is no user or the user is expired
    /// @param tokenId The NFT to get the user address for
    /// @return The user address for this NFT
    function userOf(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        if (uint256(users[tokenId].expires) >= block.timestamp) {
            return users[tokenId].user;
        } else {
            return address(0);
        }
    }

    /// @notice Get the user expires of an NFT
    /// @dev The zero value indicates that there is no user
    /// @param tokenId The NFT to get the user expires for
    /// @return The user expires for this NFT
    function userExpires(uint256 tokenId)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return users[tokenId].expires;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        if (
            from != to &&
            users[tokenId].user != address(0) //user present
        ) {
            delete users[tokenId];
            emit UpdateUser(tokenId, address(0), 0);
        }
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
        require(
            !state.initialized,
            "Already initialized"
        );

        state.initialized = true;

        _;
    }
}
