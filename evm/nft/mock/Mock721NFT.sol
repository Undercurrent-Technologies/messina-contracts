// contracts/Mock721NFT.sol
// SPDX-License-Identifier: Apache 2

// This is a 721 MockNFT following the Messina1155 Standard

pragma solidity ^0.8.0;

import "../token/Messina721.sol";
import "../../libraries/external/BytesLib.sol";

contract Mock721NFT is Messina721 {

    using BytesLib for bytes;
    using BytesLib for string;

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

    function setChainId(uint16 _chainId) public virtual onlyOwner {
        state.chainId = _chainId;
    }

    function setNativeContract(bytes32 _nativeContract) public virtual onlyOwner {
        state.nativeContract = _nativeContract;
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


    // Just an Example
    function getDecodedCreateData() external view returns (CreateData memory) {
        CreateData memory createData;
        // use to store length of uri/array, max of uint16 is 65535 which should be enough on most cases
        uint16 length;
        uint256 index; 
        bytes memory encoded = state.data; 

        // Get testAddress 
        createData.testAddress = encoded.toAddress(index);
        index += 20;// increase the index by 20, because address is 20 btyes

        // Get Amount
        createData.amount = encoded.toUint256(index);
        index += 32; // increase the index by 32, because uinr256 is 32 btyes

        // Array
        length = encoded.toUint16(index);
        index += 2; // myArray.length is uint16 which takes 2 index

        // create an array to store encoded array values
        uint256[] memory arrayValues = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            arrayValues[i] = encoded.toUint256(index); 
            index += 32; // the array values encoded are uint256, so add 32 after every iteration
        }

        // store the array
        createData.array = arrayValues;

        // URI String
        length = encoded.toUint16(index);
        index += 2;

        // slice the encoded bytes for the string within index <-> index + length
        // then convert to hexString & convert to Ascii to get the string
        string memory hexStr = encoded.slice(index, length).hexString();
        createData.uri = hexStr.hexToAscii();

        return createData;
    }


    function getDecodedMintData(uint256 tokenId) external view returns (MintData memory) {
        MintData memory mintData;
        // use to store length of uri/array, max of uint16 is 65535 which should be enough on most cases
        uint256 index;
        bytes memory encoded = state.tokenData[tokenId]; 

        // Get testAddress 
        mintData.testAddress = encoded.toAddress(index);
        index += 20;// increase the index by 20, because address is 20 btyes

        // Get Amount
        mintData.amount = encoded.toUint256(index);

        return mintData;
    }
}
