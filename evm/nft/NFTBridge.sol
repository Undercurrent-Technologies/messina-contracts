// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../libraries/external/BytesLib.sol";
import "../libraries/external/CommonStructs.sol";

import "./NFTBridgeGetters.sol";
import "./NFTBridgeSetters.sol";
import "./NFTBridgeStructs.sol";
import "./NFTBridgeGovernance.sol";

import "./token/NFT.sol";
import "./token/NFTImplementation.sol";
import "../interfaces/IMessina721.sol";

import "./1155token/NFT1155Implementation.sol";
import "../interfaces/IMessina1155.sol";
import "../interfaces/IERC4907.sol";
import "../interfaces/INFTBridgeHelper.sol";
import "../interfaces/IRoyaltyEngineV1.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/IOwnable.sol";

contract NFTBridge is NFTBridgeGovernance, ReentrancyGuard {
    using BytesLib for bytes;
    using BytesLib for bytes32;
    using BytesLib for address;
    using CommonStructs for string;
    using Strings for uint32;
    using Strings for uint8;

    struct TransferTokenDetails {
        uint16 tokenChain;
        bytes32 tokenAddress;
        string uriString;
        bytes queriedURI;
        uint256 firstTokenID;
    }

    struct WrappedNFTAssetArgs {
        uint16 tokenChain;
        bytes32 tokenAddress;
        bytes constructorArgs;
        bytes initialisationArgs;
        address beaconAddr;
        bytes4 selectorBytes;
        RoyaltyInfo royaltyInfo;
    }

    struct RoyaltyInfo {
        address royaltyAddress;
        uint96 royaltyBips;
    }

    struct UserInfo {
        address user; // address of user role
        uint256 expires; // unix timestamp, user expires
    }

    struct AdditionalData {
        uint16 standardID;
        bytes data;
        bytes mintData;
    }

    struct TokenInfo {
        uint8 tokenType;
        bytes32 symbol;
        bytes32 name;
        bytes32 collectionOwner;
        UserInfo rentUserInfo;
        AdditionalData additionalData;
        RoyaltyInfo royaltyInfo;
    }

    struct SupportStatus {
        bool is721;
        bool is1155;
        bool isMessina721;
        bool isMessina1155;
        bool isERC4907;
        bool isERC2981;
    }

    error BridgeError(string message);

    error IncorrectWrappedAssetStandard();

    modifier whenNotPaused() {
        require(!isPaused(), "contract paused");
        _;
    }

    // Initiate a Transfer
    function transferNFT(
        address token,
        uint256[] memory tokenIDs,
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        uint256[] memory amounts,
        string memory network
    ) public payable whenNotPaused nonReentrant {
        uint256 tokenIdsLen = tokenIDs.length;
        require(
            amounts.length == tokenIdsLen,
            "tokenAmounts and tokenIDs length mismatch"
        );
        require(tokenIdsLen > 0, "No token IDs provided");
        require(tokenIdsLen <= 40, "The maximum number of token IDs for bridging is 40");
        require(recipient != bytes32(0), "Recipient cannot be a 0 address");
        require(token != address(0), "NFT address cannot be 0 address");

        // Check if token address blacklisted
        require(!isCollectionBlacklisted[token], "NFT Collection Address blacklisted for bridging");

        // Process token info
        (
            TokenInfo memory tokenInfo,
            TransferTokenDetails memory transferDetails
        ) = processTokenInfo(token, tokenIDs);

        require(
            msg.value - router().messageFee(network) == state.fee,
            "incorrect fees"
        );

        detectnTransferNFTBatch(
            token,
            msg.sender,
            transferDetails.tokenChain,
            tokenIDs,
            amounts
        );

        logTransfer(
            CommonStructs.Transfer({
                tokenAddress: transferDetails.tokenAddress,
                tokenChain: transferDetails.tokenChain,
                name: tokenInfo.name,
                symbol: tokenInfo.symbol,
                tokenID: transferDetails.firstTokenID,
                standardID: tokenInfo.additionalData.standardID,
                collectionOwner: tokenInfo.collectionOwner,
                tokenType: tokenInfo.tokenType,
                tokenIDs: tokenIDs,
                tokenAmounts: amounts,
                royaltyAddress: bytes32(
                    uint256(uint160(tokenInfo.royaltyInfo.royaltyAddress))
                ),
                royaltyBips: tokenInfo.royaltyInfo.royaltyBips,
                rentAddress: bytes32(
                    uint256(uint160(tokenInfo.rentUserInfo.user))
                ),
                rentExpiryDate: tokenInfo.rentUserInfo.expires,
                uri: transferDetails.uriString,
                to: recipient,
                toChain: recipientChain,
                data: tokenInfo.additionalData.data,
                mintData: tokenInfo.additionalData.mintData
            }),
            msg.value - state.fee,
            nonce,
            network
        );

        // Send the fee to the treasury address
        address payable treasuryAddr = payable(state.treasuryAddr);
        treasuryAddr.transfer(state.fee);
    }

    function processTokenInfo(
        address token,
        uint256[] memory tokenIDs
    )
        internal
        returns (
            TokenInfo memory tokenInfo,
            TransferTokenDetails memory transferDetails
        )
    {
        transferDetails.firstTokenID = tokenIDs[0];
        SupportStatus memory supportStatus = checkSupportStatus(token);

        // Verify that the correct interfaces are implemented
        require(
            supportStatus.is721 || supportStatus.is1155,
            "for ERC721: must support the IERC721 & ERC721-Metadata extension, for ERC1155: must support the IERC1155 & ERC1155-MetadataURI extension"
        );

        if (isWrappedAsset(token)) {
            require(
                (supportStatus.is1155 && supportStatus.isMessina1155) || (supportStatus.is721 && supportStatus.isMessina721),
                "Wrapped Asset not supporting ERC-1155 & Messina1155 Standard or ERC-721 & Messina721 Standard"
            );

            if (supportStatus.is1155 && supportStatus.isMessina1155) {
                (
                    transferDetails.tokenChain,
                    transferDetails.tokenAddress
                ) = IMessina1155(token).getChainIdNNativeContract();
            } else if (supportStatus.is721 && supportStatus.isMessina721) {
                (
                    transferDetails.tokenChain,
                    transferDetails.tokenAddress
                ) = IMessina721(token).getChainIdNNativeContract();
            }
        } else {
            if (supportStatus.isMessina721) {
                transferDetails.tokenAddress = IMessina721(token)
                    .getNativeContract();
            } else if (supportStatus.isMessina1155) {
                transferDetails.tokenAddress = IMessina1155(token)
                    .getNativeContract();
            } else {
                transferDetails.tokenAddress = bytes32(uint256(uint160(token)));
            }

            transferDetails.tokenChain = chainId();
        }

        require(
            transferDetails.tokenAddress != bytes32(0),
            "native NFT address cannot be 0 address"
        );

        if (supportStatus.is721) {
            tokenInfo.tokenType = 1;
        } else if (supportStatus.is1155) {
            tokenInfo.tokenType = 2; // 1 is for 721 and 2 is for 1155
        }

        if (supportStatus.isERC4907) {
            tokenInfo.rentUserInfo.user = IERC4907(token).userOf(
                transferDetails.firstTokenID
            );
            tokenInfo.rentUserInfo.expires = IERC4907(token).userExpires(
                transferDetails.firstTokenID
            );
        }

        string memory symbolString;
        string memory nameString;
        bytes32 symbol;
        bytes32 name;

        {
            if (supportStatus.is1155) {
                // 1155: there's no name and symbol
                (, transferDetails.queriedURI) = token.staticcall(
                    abi.encodeWithSignature(
                        "uri(uint256)",
                        transferDetails.firstTokenID
                    )
                );
            } else {
                // SPL uses cache
                if (transferDetails.tokenChain != 1) {
                    (symbolString, nameString) = getSymbolAndName(token);
                }

                (, transferDetails.queriedURI) = token.staticcall(
                    abi.encodeWithSignature(
                        "tokenURI(uint256)",
                        transferDetails.firstTokenID
                    )
                );
            }

            transferDetails.uriString = abi.decode(
                transferDetails.queriedURI,
                (string)
            );
        }

        if (transferDetails.tokenChain == 1) {
            // use cached SPL token info, as the contracts uses unified values
            NFTBridgeStorage.SPLCache memory cache = splCache(
                transferDetails.firstTokenID
            );
            symbol = cache.symbol;
            name = cache.name;
            clearSplCache(transferDetails.firstTokenID);
        } else {
            assembly {
                // first 32 bytes hold string length
                // mload then loads the next word, i.e. the first 32 bytes of the strings
                // NOTE: this means that we might end up with an
                // invalid utf8 string (e.g. if we slice an emoji in half).  The VAA
                // payload specification doesn't require that these are valid utf8
                // strings, and it's cheaper to do any validation off-chain for
                // presentation purposes
                symbol := mload(add(symbolString, 32))
                name := mload(add(nameString, 32))
            }
        }

        tokenInfo.symbol = symbol;
        tokenInfo.name = name;

        // get collection Owner Addr
        address tempCollectionOwner;
        if (supportStatus.isMessina721 || supportStatus.isMessina1155) {
            if (supportStatus.isMessina721) {
                tempCollectionOwner = IMessina721(token).getOwner();
            } else {
                tempCollectionOwner = IMessina1155(token).getOwner();
            }
        } else {
            try IOwnable(token).owner() returns (
                address collectionOwner
            ) {
                tempCollectionOwner = collectionOwner;
            } catch (bytes memory /*lowLevelData*/) {
                tempCollectionOwner = address(this);
            }
        }

        tokenInfo.collectionOwner = bytes32(uint256(uint160(tempCollectionOwner)));

        if (supportStatus.isERC2981) {
            uint256 royaltyAmount;
            (tokenInfo.royaltyInfo.royaltyAddress, royaltyAmount) = IERC2981(
                token
            ).royaltyInfo(transferDetails.firstTokenID, 1 ether);
            tokenInfo.royaltyInfo.royaltyBips = uint96(
                (royaltyAmount * 10000) / 1 ether
            );
        } else if (state.royaltyRegistryAddr.isContract()) {
            // check if is a valid contract and try call
            try
                IRoyaltyEngineV1(state.royaltyRegistryAddr).getRoyaltyView(
                    token,
                    transferDetails.firstTokenID,
                    1 ether
                )
            returns (
                address payable[] memory recipients,
                uint256[] memory royaltyAmounts
            ) {
                if (recipients.length > 0 && royaltyAmounts.length > 0) {
                    tokenInfo.royaltyInfo.royaltyAddress = recipients[0];
                    tokenInfo.royaltyInfo.royaltyBips = uint96(
                        (royaltyAmounts[0] * 10000) / 1 ether
                    );
                }
            } catch (bytes memory /*lowLevelData*/) {
                // Do nothing, as default value is zero address and 0
            }
        }

        if (supportStatus.isMessina721) {
            (
                tokenInfo.additionalData.data,
                tokenInfo.additionalData.standardID
            ) = IMessina721(token).getCreateDataNStandardID();

            tokenInfo.additionalData.mintData = IMessina721(token).getMintData(
                transferDetails.firstTokenID
            );
        } else if (supportStatus.isMessina1155) {
            (
                tokenInfo.additionalData.data,
                tokenInfo.additionalData.standardID
            ) = IMessina1155(token).getCreateDataNStandardID();
        }
    }

    function logTransfer(
        CommonStructs.Transfer memory transfer,
        uint256 callValue,
        uint32 nonce,
        string memory network
    ) internal {
        bytes memory encoded = INFTBridgeHelper(state.helperAddr)
            .encodeTransfer(transfer);

        router().publishMessage{value: callValue}(network, callValue, nonce, encoded, finality());
    }

    function completeTransfer(
        bytes memory encodedVm,
        string memory network
    ) public whenNotPaused nonReentrant {
        _completeTransfer(encodedVm, network);
    }

    // Execute a Transfer message
    function _completeTransfer(bytes memory encodedVm, string memory network) internal {

        (IWormhole.VM memory vm, bool valid, string memory reason) = router()
            .parseAndVerifyVM(network, encodedVm);

        require(valid, reason);

        require(verifyBridgeVM(vm), "invalid emitter");

        CommonStructs.Transfer memory transfer = INFTBridgeHelper(
            state.helperAddr
        ).parseTransfer(vm.payload);

        require(!isTransferCompleted(vm.hash), "transfer already completed");
        setTransferCompleted(vm.hash);

        require(transfer.toChain == chainId(), "invalid target chain");
        require(transfer.to != bytes32(0), "receiver cannot be 0 address");

        uint256 transferSingleTokenId = 0;
        if (vm.emitterChainId == 8 && transfer.tokenChain == 8) {
            // If bridging from Algorand chain
            require(transfer.tokenAmounts.length == 1 && transfer.tokenIDs.length == 0, "tokenAmounts[] length should == 1 & tokenIds[] length should be 0 for algorand chain");
            transferSingleTokenId = 0; // since its empty array for algorand tokenIds[] accessing tokenIds[0] will cause revert err
        } else {
            // If bridging from a non-Algorand chain
            require(
                transfer.tokenAmounts.length == transfer.tokenIDs.length,
                "tokenAmounts and tokenIDs length mismatch"
            );
            require(transfer.tokenIDs.length > 0, "No token IDs provided");
            transferSingleTokenId = transfer.tokenIDs[0];
        }
        require(transfer.tokenAmounts.length <= 40, "The maximum number of token IDs for bridging is 40");

        require(
            transfer.tokenAddress != bytes32(0),
            "native NFT address cannot be 0 address"
        );

        require(
            transfer.tokenType == 2 || transfer.tokenType == 1,
            "Token Type can only be 1 or 2, which stands for ERC721 or ERC1155"
        );

        // Bridging 1155 NFT is not allowed for solana chain
        if (transfer.tokenType == 2) {
            require(
                transfer.tokenChain != 1,
                "ERC-1155 NFTs are not supported on the Solana chain"
            );
        }

        address transferToken;
        if (transfer.tokenChain == chainId()) {
            transferToken = address(uint160(uint256(transfer.tokenAddress)));
        } else {
            address wrapped = wrappedAsset(
                transfer.tokenChain,
                transfer.tokenAddress
            );

            // If the wrapped asset does not exist yet, create it
            if (wrapped == address(0)) {
                CommonStructs.NFTInitArgs memory initArgs = state.nftInitArgs[
                    transfer.standardID
                ];

                (
                    uint16 tokenChain,
                    bytes32 tokenAddress,
                    address token
                ) = INFTBridgeHelper(state.helperAddr).createWrapped(
                        transfer,
                        initArgs,
                        state.messina721Beacon,
                        state.messina1155Beacon,
                        state.nftBeacon[transfer.standardID],
                        address(this)
                    );

                _setWrappedAsset(tokenChain, tokenAddress, token);
                wrapped = token;
            }

            transferToken = wrapped;
        }

        // transfer bridged NFT to recipient
        address transferRecipient = address(uint160(uint256(transfer.to)));

        bool is721 = suppportI721nI721Metadata(transferToken);
        bool is1155 = suppportI1155nI1155Metadata(transferToken);

        // Verify that the correct interfaces are implemented
        require(
            is721 || is1155,
            "NFT involved in completeTransfer() for ERC721: must support the IERC721 & IERC721-Metadata extension, Wrapped Address for ERC1155: must support the IERC1155 & ERC1155-MetadataURI extension"
        );

        if (is1155) {
            if (
                transfer.tokenChain != chainId() ||
                ERC165(transferToken).supportsInterface(
                    type(IMessina1155).interfaceId
                )
            ) {
                if (transfer.tokenAmounts.length > 1) {
                    IMessina1155(transferToken).bridgeMintBatch(
                        transferRecipient,
                        transfer.tokenIDs,
                        transfer.tokenAmounts,
                        ""
                    );
                } else {
                    IMessina1155(transferToken).bridgeMint(
                        transferRecipient,
                        transferSingleTokenId,
                        transfer.tokenAmounts[0],
                        ""
                    );
                }
            } else {
                if (transfer.tokenAmounts.length > 1) {
                    IERC1155(transferToken).safeBatchTransferFrom(
                        address(this),
                        transferRecipient,
                        transfer.tokenIDs,
                        transfer.tokenAmounts,
                        ""
                    );
                } else {
                    IERC1155(transferToken).safeTransferFrom(
                        address(this),
                        transferRecipient,
                        transferSingleTokenId,
                        transfer.tokenAmounts[0],
                        ""
                    );
                }
            }
        } else {
            if (
                transfer.tokenChain != chainId() ||
                ERC165(transferToken).supportsInterface(
                    type(IMessina721).interfaceId
                )
            ) {
                if (transfer.tokenChain == 1) {
                    // Cache SPL token info which otherwise would get lost
                    setSplCache(
                        transfer.tokenID,
                        NFTBridgeStorage.SPLCache({
                            name: transfer.name,
                            symbol: transfer.symbol
                        })
                    );
                }

                // mint wrapped asset
                IMessina721(transferToken).bridgeMint(
                    transferRecipient,
                    transferSingleTokenId,
                    transfer.uri,
                    transfer.mintData
                );
            } else {
                IERC721(transferToken).safeTransferFrom(
                    address(this),
                    transferRecipient,
                    transferSingleTokenId
                );
            }

            // set RentInfo if Bridge Approved and is4907
            // Using a try-catch here because we have already made a tweak to ERC4907 to allow NFTBridge to setUser without approval
            // And not using an if statement to check if NFTBridge is approved, because we generate a new contract for the first bridging process of a origin collection and setting approval to the NFTBridge for the first bridge process is not possible
            if (
                ERC165(transferToken).supportsInterface(
                    type(IERC4907).interfaceId
                )
            ) {
                try
                    IERC4907(transferToken).setUser(
                        transferSingleTokenId,
                        address(uint160(uint256(transfer.rentAddress))),
                        uint64(transfer.rentExpiryDate)
                    )
                {} catch (bytes memory /*lowLevelData*/) {
                    // Do nothing, as default value is zero address and 0
                }
            }
        }
    }

    function verifyBridgeVM(
        IWormhole.VM memory vm
    ) internal view returns (bool) {
        if (bridgeContracts(vm.emitterChainId) == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(
            operator == address(this),
            "can only bridge tokens via transferNFT method"
        );
        return type(IERC721Receiver).interfaceId;
    }

    function onERC1155Received(
        address operator,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(
            operator == address(this),
            "can only bridge tokens via transferNFT method"
        );
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external view returns (bytes4) {
        require(
            operator == address(this),
            "can only bridge tokens via transferNFT method"
        );
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function suppportI721nI721Metadata(
        address token
    ) internal view returns (bool) {
        return (ERC165(token).supportsInterface(type(IERC721).interfaceId) &&
            ERC165(token).supportsInterface(type(IERC721Metadata).interfaceId));
    }

    function suppportI1155nI1155Metadata(
        address token
    ) internal view returns (bool) {
        return (ERC165(token).supportsInterface(type(IERC1155).interfaceId) &&
            ERC165(token).supportsInterface(
                type(IERC1155MetadataURI).interfaceId
            ));
    }

    function getSymbolAndName(address token)
        internal
        view
        returns (string memory, string memory)
    {
        (, bytes memory queriedSymbol) = token.staticcall(
            abi.encodeWithSignature("symbol()")
        );
        (, bytes memory queriedName) = token.staticcall(
            abi.encodeWithSignature("name()")
        );
        string memory symbolString = abi.decode(queriedSymbol, (string));
        string memory nameString = abi.decode(queriedName, (string));
        return (symbolString, nameString);
    }

    function checkSupportStatus(address token) internal view returns (SupportStatus memory) {
        bool is721 = suppportI721nI721Metadata(token);
        bool is1155 = suppportI1155nI1155Metadata(token);
        bool isMessina721 = ERC165(token).supportsInterface(
            type(IMessina721).interfaceId
        );
        bool isMessina1155 = ERC165(token).supportsInterface(
            type(IMessina1155).interfaceId
        );
        bool isERC4907 = ERC165(token).supportsInterface(
            type(IERC4907).interfaceId
        );
        bool isERC2981 = ERC165(token).supportsInterface(
            type(IERC2981).interfaceId
        );
        return SupportStatus({
            is721: is721,
            is1155: is1155,
            isMessina721: isMessina721,
            isMessina1155: isMessina1155,
            isERC4907: isERC4907,
            isERC2981: isERC2981
        });
    }

    function detectnTransferNFTBatch(
        address token,
        address sender,
        uint16 tokenChain,
        uint256[] memory tokenIDs,
        uint256[] memory amounts
    ) internal {
        // since checked that tokenIDs.length == amounts.length, just check amounts.length here is enough
        require(
            amounts.length > 0,
            "tokenIds and amounts length must be more than 0"
        );

        if (suppportI1155nI1155Metadata(token)) {
            if (tokenIDs.length == 1) {
                IERC1155(token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    tokenIDs[0],
                    amounts[0],
                    ""
                );
                if (
                    tokenChain != chainId() ||
                    ERC165(token).supportsInterface(
                        type(IMessina1155).interfaceId
                    )
                ) {
                    IMessina1155(token).bridgeBurn(
                        address(this),
                        tokenIDs[0],
                        amounts[0]
                    );
                }
            } else {
                IERC1155(token).safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    tokenIDs,
                    amounts,
                    ""
                );
                if (
                    tokenChain != chainId() ||
                    ERC165(token).supportsInterface(
                        type(IMessina1155).interfaceId
                    )
                ) {
                    IMessina1155(token).bridgeBurnBatch(
                        address(this),
                        tokenIDs,
                        amounts
                    );
                }
            }
        } else {
            // since checked that tokenIDs.length == amounts.length, just check tokenIDs.length here is enough
            require(
                tokenIDs.length == 1,
                "ERC721 should only transfer one tokenIDs"
            );
            require(
                amounts[0] == 1,
                "ERC721 should have only transfer with amount of 1"
            );
            IERC721(token).safeTransferFrom(sender, address(this), tokenIDs[0]);
            if (
                tokenChain != chainId() ||
                ERC165(token).supportsInterface(type(IMessina721).interfaceId)
            ) {
                IMessina721(token).bridgeBurn(tokenIDs[0]);
            }
        }
    }
}

// // Creates a wrapped asset using AssetMeta
// function _createWrapped(
//     uint16 tokenChain,
//     bytes32 tokenAddress,
//     bytes32 name,
//     bytes32 symbol,
//     string memory uri,
//     uint8 tokenType,
//     bytes32 royaltyAddress,
//     uint96 royaltyBips,
//     uint16 standardID,
//     bytes memory data
// ) internal returns (address token) {
//     require(
//         tokenChain != chainId(),
//         "can only wrap tokens from foreign chains"
//     );
//     require(
//         wrappedAsset(tokenChain, tokenAddress) == address(0),
//         "wrapped asset already exists"
//     );

//     WrappedNFTAssetArgs memory wrappedNFTAssetArgs;
//     wrappedNFTAssetArgs.tokenAddress = tokenAddress;
//     wrappedNFTAssetArgs.tokenChain = tokenChain;
//     wrappedNFTAssetArgs.royaltyInfo.royaltyAddress = address(
//         uint160(uint256(royaltyAddress))
//     );
//     wrappedNFTAssetArgs.royaltyInfo.royaltyBips = royaltyBips;

//     // SPL NFTs all use the same NFT contract, so unify the name
//     if (tokenChain == 1) {
//         // "Wormhole Bridged Solana-NFT" - right-padded
//         name = 0x576f726d686f6c65204272696467656420536f6c616e612d4e46540000000000;
//         // "WORMSPLNFT" - right-padded
//         symbol = 0x574f524d53504c4e465400000000000000000000000000000000000000000000;
//     }

//     bytes memory bytecode;
//     NFTBridgeStorage.NFTInitArgs memory initArgs = state.nftInitArgs[
//         standardID
//     ];
//     if (standardID == 0) {
//         // if standardID 0 means is non-messina or messina standrd which will use the default 721 or 1155 beacon
//         if (tokenType == 2) {
//             wrappedNFTAssetArgs.beaconAddr = state.messina1155Beacon;
//             wrappedNFTAssetArgs.selectorBytes = NFT1155Implementation
//                 .initialize
//                 .selector;
//         } else {
//             wrappedNFTAssetArgs.beaconAddr = state.messina721Beacon;
//             wrappedNFTAssetArgs.selectorBytes = NFTImplementation
//                 .initialize
//                 .selector;
//         }
//     } else {
//         // else if standardID not 0, means its other NFTImplementation and have their own beacon
//         wrappedNFTAssetArgs.beaconAddr = state.nftBeacon[standardID];
//         wrappedNFTAssetArgs.selectorBytes = initArgs.selectorBytes;
//     }

//     require(
//         wrappedNFTAssetArgs.beaconAddr != address(0),
//         "Beacon Address is 0 address"
//     );
//     // TokenType 2 is 1155, 1 is 721
//     if (tokenType == 2) {
//         // initialize the NFT1155Implementation
//         wrappedNFTAssetArgs.initialisationArgs = abi.encodeWithSelector(
//             wrappedNFTAssetArgs.selectorBytes,
//             uri,
//             initArgs.ownerAddr,
//             address(this),
//             wrappedNFTAssetArgs.tokenChain,
//             wrappedNFTAssetArgs.tokenAddress,
//             wrappedNFTAssetArgs.royaltyInfo.royaltyAddress,
//             wrappedNFTAssetArgs.royaltyInfo.royaltyBips,
//             standardID,
//             data
//         );
//     } else {
//         // initialize the NFTImplementation
//         wrappedNFTAssetArgs.initialisationArgs = abi.encodeWithSelector(
//             wrappedNFTAssetArgs.selectorBytes,
//             name.bytes32ToString(),
//             symbol.bytes32ToString(),
//             initArgs.ownerAddr,
//             address(this),
//             wrappedNFTAssetArgs.tokenChain,
//             wrappedNFTAssetArgs.tokenAddress,
//             wrappedNFTAssetArgs.royaltyInfo.royaltyAddress,
//             wrappedNFTAssetArgs.royaltyInfo.royaltyBips,
//             standardID,
//             data
//         );
//     }

//     // initialize the BeaconProxy
//     wrappedNFTAssetArgs.constructorArgs = abi.encode(
//         wrappedNFTAssetArgs.beaconAddr,
//         wrappedNFTAssetArgs.initialisationArgs
//     );

//     // deployment code
//     bytecode = abi.encodePacked(
//         type(BridgeNFT).creationCode,
//         wrappedNFTAssetArgs.constructorArgs
//     );

//     bytes32 salt = keccak256(
//         abi.encodePacked(
//             wrappedNFTAssetArgs.tokenChain,
//             wrappedNFTAssetArgs.tokenAddress
//         )
//     );

//     assembly {
//         token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

//         if iszero(extcodesize(token)) {
//             mstore(0x80, shl(229, 4594637))
//             mstore(0x84, 32)
//             mstore(0xA4, 30)
//             mstore(0xC4, "Error at Create Wrapped")
//             revert(0x80, 0x64)
//             // revert(0, 0)
//         }
//     }

//     _setWrappedAsset(
//         wrappedNFTAssetArgs.tokenChain,
//         wrappedNFTAssetArgs.tokenAddress,
//         token
//     );
// }

// function getSelectorBytes() external view virtual returns (bytes4) {
//     // if(_type == 1) {
//     //         return NFTImplementation.initialize.selector;
//     // } else {
//         return NFT1155Implementation.initialize.selector;
//     // }
// }

// Prev TransferNFT for 721 and 1155 with single tokenId
// // Initiate a Transfer
// function transferNFT(address token, uint256 tokenID, uint16 recipientChain, bytes32 recipient, uint32 nonce, uint256 amount) public payable returns (uint64 sequence) {
//     // determine token parameters
//     TransferTokenDetails memory transferDetails;

//     if (isWrappedAsset(token)) {
//         if(ERC165(token).supportsInterface(type(IERC1155).interfaceId)) {
//             transferDetails.tokenChain = NFT1155Implementation(token).getChainId();
//             transferDetails.tokenAddress = NFT1155Implementation(token).getNativeContract();
//         } else {
//             transferDetails.tokenChain = NFTImplementation(token).getChainId();
//             transferDetails.tokenAddress = NFTImplementation(token).getNativeContract();
//         }
//     } else {
//         // Verify that the correct interfaces are implemented
//         require(suppportI721nI721Metadata(token) || suppportI1155nI1155Metadata(token),
//             "for ERC721: must support the IERC721 & ERC721-Metadata extention, for ERC1155: must support the IERC1155 & ERC1155-MetadataURI extention"
//         );
//         transferDetails.tokenChain = chainId();
//         transferDetails.tokenAddress = bytes32(uint256(uint160(token)));
//     }

//     string memory symbolString;
//     string memory nameString;
//     bytes32 symbol;
//     bytes32 name;
//     {
//         if (suppportI1155nI1155Metadata(token)) {
//             // 1155: there's no name and symbol
//             (symbolString, nameString) = ("TT", "TestToken (Wormhole)");
//             (,bytes memory queriedURI) = token.staticcall(abi.encodeWithSignature("uri(uint256)", tokenID));
//             transferDetails.uriString = abi.decode(queriedURI, (string));
//         } else {
//             // SPL uses cache
//             if (transferDetails.tokenChain != 1) {
//                 (symbolString, nameString) = getSymbolAndName(token);
//             }
//             (,bytes memory queriedURI) = token.staticcall(abi.encodeWithSignature("tokenURI(uint256)", tokenID));
//             transferDetails.uriString = abi.decode(queriedURI, (string));
//         }
//     }

//     if (transferDetails.tokenChain == 1) {
//         // use cached SPL token info, as the contracts uses unified values
//         NFTBridgeStorage.SPLCache memory cache = splCache(tokenID);
//         symbol = cache.symbol;
//         name = cache.name;
//         clearSplCache(tokenID);
//     } else {
//         assembly {
//         // first 32 bytes hold string length
//         // mload then loads the next word, i.e. the first 32 bytes of the strings
//         // NOTE: this means that we might end up with an
//         // invalid utf8 string (e.g. if we slice an emoji in half).  The VAA
//         // payload specification doesn't require that these are valid utf8
//         // strings, and it's cheaper to do any validation off-chain for
//         // presentation purposes
//             symbol := mload(add(symbolString, 32))
//             name := mload(add(nameString, 32))
//         }
//     }

//     detectnTansferNFT(token, msg.sender, transferDetails.tokenChain, tokenID, amount);

//     // Should we add ERC1155/ERC721 type and amount?
//     sequence = logTransfer(NFTBridgeStructs.Transfer({
//         tokenAddress : transferDetails.tokenAddress,
//         tokenChain   : transferDetails.tokenChain,
//         name         : name,
//         symbol       : symbol,
//         tokenID      : tokenID,
//         uri          : transferDetails.uriString,
//         to           : recipient,
//         toChain      : recipientChain
//     }), msg.value, nonce);
// }

// Original transferNFT()
// // Initiate a Transfer
// function transferNFT(address token, uint256 tokenID, uint16 recipientChain, bytes32 recipient, uint32 nonce) public payable returns (uint64 sequence) {
//     // determine token parameters
//     uint16 tokenChain;
//     bytes32 tokenAddress;
//     if (isWrappedAsset(token)) {
//         tokenChain = NFTImplementation(token).getChainId();
//         tokenAddress = NFTImplementation(token).getNativeContract();
//     } else {
//         tokenChain = chainId();
//         tokenAddress = bytes32(uint256(uint160(token)));
//         // Verify that the correct interfaces are implemented
//         require(ERC165(token).supportsInterface(type(IERC721).interfaceId), "must support the ERC721 interface");
//         require(ERC165(token).supportsInterface(type(IERC721Metadata).interfaceId), "must support the ERC721-Metadata extension");
//     }

//     string memory symbolString;
//     string memory nameString;
//     string memory uriString;
//     {
//         if (tokenChain != 1) { // SPL tokens use cache
//             (,bytes memory queriedSymbol) = token.staticcall(abi.encodeWithSignature("symbol()"));
//             (,bytes memory queriedName) = token.staticcall(abi.encodeWithSignature("name()"));
//             symbolString = abi.decode(queriedSymbol, (string));
//             nameString = abi.decode(queriedName, (string));
//         }

//         (,bytes memory queriedURI) = token.staticcall(abi.encodeWithSignature("tokenURI(uint256)", tokenID));
//         uriString = abi.decode(queriedURI, (string));
//     }

//     bytes32 symbol;
//     bytes32 name;
//     if (tokenChain == 1) {
//         // use cached SPL token info, as the contracts uses unified values
//         NFTBridgeStorage.SPLCache memory cache = splCache(tokenID);
//         symbol = cache.symbol;
//         name = cache.name;
//         clearSplCache(tokenID);
//     } else {
//         assembly {
//         // first 32 bytes hold string length
//         // mload then loads the next word, i.e. the first 32 bytes of the strings
//         // NOTE: this means that we might end up with an
//         // invalid utf8 string (e.g. if we slice an emoji in half).  The VAA
//         // payload specification doesn't require that these are valid utf8
//         // strings, and it's cheaper to do any validation off-chain for
//         // presentation purposes
//             symbol := mload(add(symbolString, 32))
//             name := mload(add(nameString, 32))
//         }
//     }

//     IERC721(token).safeTransferFrom(msg.sender, address(this), tokenID);
//     // need to change the InterfaceID if finalise MNFT standard
//     if (tokenChain != chainId() || ERC165(token).supportsInterface(type(IMessina721).interfaceId)) {
//         NFTImplementation(token).bridgeBurn(tokenID);
//     }

//     sequence = logTransfer(NFTBridgeStructs.Transfer({
//         tokenAddress : tokenAddress,
//         tokenChain   : tokenChain,
//         name         : name,
//         symbol       : symbol,
//         tokenID      : tokenID,
//         uri          : uriString,
//         to           : recipient,
//         toChain      : recipientChain
//     }), msg.value, nonce);
// }

// Prev TransferNFT for 721 and 1155 with single tokenId
// // Execute a Transfer message
// function _completeTransfer(bytes memory encodedVm) internal {
//     (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

//     require(valid, reason);
//     require(verifyBridgeVM(vm), "invalid emitter");

//     NFTBridgeStructs.Transfer memory transfer = parseTransfer(vm.payload);

//     require(!isTransferCompleted(vm.hash), "transfer already completed");
//     setTransferCompleted(vm.hash);

//     require(transfer.toChain == chainId(), "invalid target chain");

//     address transferToken;
//     if (transfer.tokenChain == chainId()) {
//         transferToken = address(uint160(uint256(transfer.tokenAddress)));
//     } else {
//         address wrapped = wrappedAsset(transfer.tokenChain, transfer.tokenAddress);

//         // If the wrapped asset does not exist yet, create it
//         if (wrapped == address(0)) {
//             // Currently HARDCODED here, Need to have a transfer.NFTTtype for whether its 1155 or 721
//             // if (address(uint160(uint256(transfer.tokenAddress))) != address(0)){
//             //     wrapped = _create1155Wrapped(transfer.tokenChain, transfer.tokenAddress, transfer.uri);
//             // } else {
//                 // wrapped = _createWrapped(transfer.tokenChain, transfer.tokenAddress, transfer.name, transfer.symbol, transfer.uri);
//                 wrapped = _createWrapped(transfer.tokenChain, transfer.tokenAddress, transfer.name, transfer.symbol, transfer.uri);
//             // }
//         }

//         transferToken = wrapped;
//     }

//     // transfer bridged NFT to recipient
//     address transferRecipient = address(uint160(uint256(transfer.to)));

//     if (ERC165(transferToken).supportsInterface(type(IERC1155).interfaceId)){
//         if (transfer.tokenChain != chainId() || ERC165(transferToken).supportsInterface(type(IMessina1155).interfaceId)) {
//             if (transfer.tokenChain == 1) {
//                 // Cache SPL token info which otherwise would get lost
//                 setSplCache(transfer.tokenID, NFTBridgeStorage.SPLCache({
//                     name : transfer.name,
//                     symbol : transfer.symbol
//                 }));
//             }

//             // mint wrapped asset
//             // the amount of "1" is HARDCODED, should need to configure the payload and use transfer.amount
//             NFT1155Implementation(transferToken).bridgeMint(transferRecipient, transfer.tokenID, 1, "");
//         } else {
//             // the amount of "1" is HARDCODED, should need to configure the payload and use transfer.amount
//             IERC1155(transferToken).safeTransferFrom(address(this), transferRecipient, transfer.tokenID, 1, "");
//         }
//     } else {
//         // need to change the InterfaceID if finalise MNFT standard
//         if (transfer.tokenChain != chainId() || ERC165(transferToken).supportsInterface(type(IMessina721).interfaceId)) {
//             if (transfer.tokenChain == 1) {
//                 // Cache SPL token info which otherwise would get lost
//                 setSplCache(transfer.tokenID, NFTBridgeStorage.SPLCache({
//                     name : transfer.name,
//                     symbol : transfer.symbol
//                 }));
//             }

//             // mint wrapped asset
//             NFTImplementation(transferToken).bridgeMint(transferRecipient, transfer.tokenID, transfer.uri);
//         } else {
//             IERC721(transferToken).safeTransferFrom(address(this), transferRecipient, transfer.tokenID);
//         }
//     }
// }

// Original _completeTransfer
// // Execute a Transfer message
// function _completeTransfer(bytes memory encodedVm) internal {
//     (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

//     require(valid, reason);
//     require(verifyBridgeVM(vm), "invalid emitter");

//     NFTBridgeStructs.Transfer memory transfer = parseTransfer(vm.payload);

//     require(!isTransferCompleted(vm.hash), "transfer already completed");
//     setTransferCompleted(vm.hash);

//     require(transfer.toChain == chainId(), "invalid target chain");

//     IERC721 transferToken;
//     if (transfer.tokenChain == chainId()) {
//         transferToken = IERC721(address(uint160(uint256(transfer.tokenAddress))));
//     } else {
//         address wrapped = wrappedAsset(transfer.tokenChain, transfer.tokenAddress);

//         // If the wrapped asset does not exist yet, create it
//         if (wrapped == address(0)) {
//             wrapped = _createWrapped(transfer.tokenChain, transfer.tokenAddress, transfer.name, transfer.symbol);
//         }

//         transferToken = IERC721(wrapped);
//     }

//     // transfer bridged NFT to recipient
//     address transferRecipient = address(uint160(uint256(transfer.to)));

//     // need to change the InterfaceID if finalise MNFT standard
//     if (transfer.tokenChain != chainId() || ERC165(address(transferToken)).supportsInterface(type(IMessina721).interfaceId)) {
//         if (transfer.tokenChain == 1) {
//             // Cache SPL token info which otherwise would get lost
//             setSplCache(transfer.tokenID, NFTBridgeStorage.SPLCache({
//                 name : transfer.name,
//                 symbol : transfer.symbol
//             }));
//         }

//         // mint wrapped asset
//         NFTImplementation(address(transferToken)).bridgeMint(transferRecipient, transfer.tokenID, transfer.uri);
//     } else {
//         transferToken.safeTransferFrom(address(this), transferRecipient, transfer.tokenID);
//     }
// }

// // Original Create Wrapped
// // // Creates a wrapped asset using AssetMeta
// function _createWrapped(uint16 tokenChain, bytes32 tokenAddress, bytes32 name, bytes32 symbol) internal returns (address token) {
//     require(tokenChain != chainId(), "can only wrap tokens from foreign chains");
//     require(wrappedAsset(tokenChain, tokenAddress) == address(0), "wrapped asset already exists");

//     // SPL NFTs all use the same NFT contract, so unify the name
//     if (tokenChain == 1) {
//         // "Wormhole Bridged Solana-NFT" - right-padded
//         name =   0x576f726d686f6c65204272696467656420536f6c616e612d4e46540000000000;
//         // "WORMSPLNFT" - right-padded
//         symbol = 0x574f524d53504c4e465400000000000000000000000000000000000000000000;
//     }

//     // initialize the NFTImplementation
//     bytes memory initialisationArgs = abi.encodeWithSelector(
//         NFTImplementation.initialize.selector,
//    name.bytes32ToString(),
//    symbol.bytes32ToString(),
//         // need to change again after finalizing, just for testing
//         address(this),
//         address(this),
//         tokenChain,
//         tokenAddress,
//         address(0x1E7100100bad4518e5aCA0B03f8027Fc946e92Fb),
//         500
//     );

//     // initialize the BeaconProxy
//     bytes memory constructorArgs = abi.encode(address(this), initialisationArgs);

//     // deployment code
//     bytes memory bytecode = abi.encodePacked(type(BridgeNFT).creationCode, constructorArgs);

//     bytes32 salt = keccak256(abi.encodePacked(tokenChain, tokenAddress));

//     assembly {
//         token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

//         if iszero(extcodesize(token)) {
//             revert(0, 0)
//         }
//     }

//     _setWrappedAsset(tokenChain, tokenAddress, token);
// }

// function detectnTansferNFT(address token, address sender, uint16 tokenChain, uint256 tokenID, uint256 amount) internal {
//     if (suppportI1155nI1155Metadata(token)) {
//         IERC1155(token).safeTransferFrom(sender, address(this), tokenID, amount, "");
//         // need to change the InterfaceID if finalise MNFT standard
//         if (tokenChain != chainId() || ERC165(token).supportsInterface(type(IMessina1155).interfaceId)) {
//             NFT1155Implementation(token).bridgeBurn(address(this), tokenID, amount);
//         }
//         // Not sure if we need bridge multiple tokenId at once
//         // else {
//         //     IERC1155(token).safeBatchTransferFrom(sender, address(this), tokenID, amount)
//         // }
//     } else {
//         IERC721(token).safeTransferFrom(sender, address(this), tokenID);
//         // need to change the InterfaceID if finalise MNFT standard
//         if (tokenChain != chainId() || ERC165(token).supportsInterface(type(IMessina721).interfaceId)) {
//             NFTImplementation(token).bridgeBurn(tokenID);
//         }
//     }
// }
