// contracts/Messina1155.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../../../interfaces/IMessina1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// Based on the OpenZepplin ERC1155 implementation, licensed under MIT
contract Messina1155Only is
    Context,
    IERC1155,
    IERC1155MetadataURI,
    ERC165,
    IMessina1155
{
    struct State {
        // Mapping owner address to token count
        mapping(uint256 => mapping(address => uint256)) balances;
        // Mapping from owner to operator approvals
        mapping(address => mapping(address => bool)) operatorApprovals;
        // Mapping from tokenID to createData
        mapping(uint256 => bytes) tokenData;
        
        // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
        string uri;
        address owner;
        address nftBridge;
        bool initialized;
        uint16 chainId;
        uint16 standardID;
        bytes32 nativeContract;
        bytes data;
    }

    State internal _state;

    using Address for address;
    using Strings for uint256;

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
    ) {
        _state.uri = uri_;
        _state.owner = owner_;
        _state.nftBridge = nftBridge_;
        _state.chainId = chainId_;
        _state.nativeContract = bytes32(uint256(uint160(address(this))));
        abi.encode(royaltyReceiver_, royaltyFeesInBips_, nativeContract_); 
        _state.standardID = standardID_;
        _state.data = data_;
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        _mint(to, id, amount, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IMessina1155).interfaceId || // Before we finalise our own interface
            // interfaceId == type(ERC2981).interfaceId ||
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return _state.uri;
    }

    function balanceOf(address owner_, uint256 id_) public view virtual override returns (uint256) {
        require(
            owner_ != address(0),
            "ERC1155: address zero is not a valid owner"
        );
        return _state.balances[id_][owner_];
    }

    function balanceOfBatch(address[] memory owners_, uint256[] memory ids_)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(owners_.length == ids_.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](owners_.length);

        for (uint256 i = 0; i < owners_.length; ++i) {
            batchBalances[i] = balanceOf(owners_[i], ids_[i]);
        }

        return batchBalances;
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

    function getStandardID() public view virtual override returns (uint16) {
        return _state.standardID;
    }

    function getCreateDataNStandardID() public view virtual override returns (bytes memory, uint16) {
        return (_state.data, _state.standardID);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
    {
        require(operator != _msgSender(), "ERC1155: setting approval status for self");

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

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        uint256 fromBalance = _state.balances[id][from];
        require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
        unchecked {
            _state.balances[id][from] = fromBalance - amount;
        }
        _state.balances[id][to] += amount;

        emit TransferSingle(operator, from, to, id, amount);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = _state.balances[id][from];
            require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
            unchecked {
                _state.balances[id][from] = fromBalance - amount;
            }
            _state.balances[id][to] += amount;
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    function bridgeMint(address to, uint256 id, uint256 amount, bytes memory data) public virtual override onlyNFTBridge {
        _mint(to, id, amount, data);
    }

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: mint to the zero address");

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        _state.balances[id][to] += amount;
        emit TransferSingle(operator, address(0), to, id, amount);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);

        _doSafeTransferAcceptanceCheck(operator, address(0), to, id, amount, data);
    }

    function bridgeMintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public virtual override onlyNFTBridge {
        _mintBatch(to, ids, amounts, data);
    }

    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; i++) {
            _state.balances[ids[i]][to] += amounts[i];
        }

        emit TransferBatch(operator, address(0), to, ids, amounts);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);

        _doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);
    }

    function bridgeBurn(address from, uint256 tokenId, uint256 amount) public virtual override onlyNFTBridge {
        _burn(from, tokenId, amount);
    }

    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC1155: burn from the zero address");

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        uint256 fromBalance = _state.balances[id][from];
        require(fromBalance >= amount, "ERC1155: burn amount exceeds balance");
        unchecked {
            _state.balances[id][from] = fromBalance - amount;
        }

        emit TransferSingle(operator, from, address(0), id, amount);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    function bridgeBurnBatch(address from, uint256[] memory ids, uint256[] memory amounts) public virtual override onlyNFTBridge {
        _burnBatch(from, ids, amounts);
    }

    function _burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        require(from != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = _state.balances[id][from];
            require(fromBalance >= amount, "ERC1155: burn amount exceeds balance");
            unchecked {
                _state.balances[id][from] = fromBalance - amount;
            }
        }

        emit TransferBatch(operator, from, address(0), ids, amounts);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    function _setURI(string memory newuri) internal virtual {
        _state.uri = newuri;
    }

    function setNFTBridge(address newNftBridge) public virtual override onlyOwner {
        require(newNftBridge != address(0), "new owner is the zero address");
        address oldNftBridge = _state.nftBridge;
        _state.nftBridge = newNftBridge;
        emit NewNftBridgeAddress(oldNftBridge, newNftBridge);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}

    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non-ERC1155Receiver implementer");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non-ERC1155Receiver implementer");
            }
        }
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    // // ERC2981 functions

    // function setRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips)
    //     public
    //     virtual
    //     onlyOwner
    // {
    //     _setDefaultRoyalty(_receiver, _royaltyFeesInBips);
    // }

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
