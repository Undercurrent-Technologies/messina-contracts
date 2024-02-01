// contracts/MockDecodeEncode.sol
// SPDX-License-Identifier: Apache 2

// This is a MockEncodeDecode Example for getCreateData() & getMintData(tokenId)
// getEncoded() which gets the sample encodedBytes which
//     uses in messina721.js test case's createData
// getEncodedMintData() which gets the sample encodedBytes which
//     uses in messina721.js test case's mintData

pragma solidity ^0.8.0;

import "../../libraries/external/BytesLib.sol";

contract TestDecodeEncode1 {
    using BytesLib for bytes;
    using BytesLib for string;

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

    uint256[] myArray;

    function getEncoded() external returns (bytes memory) {
        address testAddress = address(
            0x65E9d8b6069eEc1Ef3b8bfaE57326008b7aec2c9
        );
        myArray.push(123);
        myArray.push(456);
        myArray.push(789);
        uint256 amount = 10;
        string memory uri = "http://";

        // encode the values to bytes
        bytes memory encoded = abi.encodePacked(
            testAddress,
            amount,
            uint16(myArray.length), // for fields like arrays or string which have dynamic length, we need to calculate the length before encoding
            myArray,
            uint16(abi.encodePacked(uri).length),
            abi.encodePacked(uri)
        );

        return encoded;
    }

    function getEncodedMintData() external pure returns (bytes memory) {
        address testAddress = address(
            0x65E9d8b6069eEc1Ef3b8bfaE57326008b7aec2c9
        );
        uint256 amount = 10;

        // encode the values to bytes
        bytes memory encoded = abi.encodePacked(testAddress, amount);

        return encoded;
    }

    function getDecoded(bytes memory encoded)
        external
        pure
        returns (CreateData memory)
    {
        // function getDecoded(bytes memory encoded) external pure returns (uint256) {
        CreateData memory createData;
        // use to store length of uri/array, max of uint16 is 65535 which should be enough on most cases
        uint16 length;
        uint256 index;

        // Get testAddress
        createData.testAddress = encoded.toAddress(index);
        index += 20; // increase the index by 20, because address is 20 btyes

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

    function getDecodedMintData(bytes memory encoded)
        external
        pure
        returns (MintData memory)
    {
        MintData memory mintData;
        // use to store length of uri/array, max of uint16 is 65535 which should be enough on most cases
        uint256 index;

        // Get testAddress
        mintData.testAddress = encoded.toAddress(index);
        index += 20; // increase the index by 20, because address is 20 btyes

        // Get Amount
        mintData.amount = encoded.toUint256(index);

        return mintData;
    }
}

/*
contract TestDecodeEncode3 {
    using BytesLib for bytes;
    using BytesLib for string;


    struct TransferData {
        // PayloadID uint8 = 1
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // Symbol of the token
        bytes32 symbol;
        // Name of the token
        bytes32 name;
        // TokenID for 721
        uint256 tokenID;
        // Token Type of the token, 1 for 721, 2 for 1155
        uint16 standardID;
        // Token Type of the token, 1 for 721, 2 for 1155
        uint8 tokenType;
        // TokenID of the token
        uint256[] tokenIDs;
        // TokenID of the token
        uint256[] tokenAmounts;
        // Royalty Address
        bytes32 royaltyAddress;
        // Royalty Bips
        uint96 royaltyBips;
        // Rent Address
        bytes32 rentAddress;
        // Rent Timestamp;
        uint256 rentExpiryDate;
        // URI of the token metadata (UTF-8)
        string uri;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        bytes32 to;
        // Chain ID of the recipient
        uint16 toChain;
        // additional data for constructor
        bytes data;
        // additional data for bridgeMint
        bytes mintData;
    }

    struct ConcatBytes{
        bytes bytes1concat;
        bytes bytes2concat;
        bytes totalBytes;
    }

    uint256[] myArray;
    uint256[] myAmounts;



    function getEncoded() external returns (bytes memory) {
       TransferData memory transferData;
       transferData.tokenAddress = 0x00000000000000000000000065e9d8b6069eec1ef3b8bfae57326008b7aec2c9;
       transferData.tokenChain = 2;
       transferData.symbol = 0x5454000000000000000000000000000000000000000000000000000000000000;
       transferData.name = 0x54657374546f6b656e0000000000000000000000000000000000000000000000;
       transferData.tokenID = 10;
       transferData.tokenType = 1;
       myArray.push(123);
       myArray.push(456);
       myAmounts.push(1);
       myAmounts.push(2);
       transferData.royaltyAddress = 0x00000000000000000000000065e9d8b6069eec1ef3b8bfae57326008b7aec2c9;
       transferData.royaltyBips = 500;
       transferData.rentAddress = 0x00000000000000000000000065e9d8b6069eec1ef3b8bfae57326008b7aec2c9;
       transferData.rentExpiryDate = 1678865324;
       transferData.uri = "https://";
       transferData.to = 0x00000000000000000000000065e9d8b6069eec1ef3b8bfae57326008b7aec2c9;
       transferData.toChain = 4;
       transferData.data = "0102030405";
       transferData.mintData = "0102030405";

       bytes memory encoded = abi.encodePacked(
            uint8(1),
            transferData.tokenAddress,
            transferData.tokenChain,
            stringToBytes32("TT"),
            stringToBytes32("TestToken (Wormhole)"),
            transferData.tokenID,
            transferData.tokenType,
            uint16(myArray.length),
            myArray,
            uint16(myAmounts.length),
            myAmounts
        );

        bytes memory encoded1 = abi.encodePacked(
            transferData.royaltyAddress,
            transferData.royaltyBips,
            transferData.rentAddress,
            transferData.rentExpiryDate,
            uint16(abi.encodePacked(transferData.uri).length),
            abi.encodePacked(transferData.uri),
            transferData.to,
            transferData.toChain,
            uint16(transferData.data.length),
            transferData.data,
            uint16(transferData.mintData.length),
            transferData.mintData
        );

        bytes memory result = abi.encodePacked(encoded, encoded1);

        return result;
    }
    
    function getDecoded(bytes memory encoded) external pure returns (TransferData memory transfer) {
    uint16 length;

        uint8 payloadID = encoded.toUint8(0);
        require(payloadID == 1, "invalid Transfer");

        uint256 index = 1;

        transfer.tokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.tokenChain = encoded.toUint16(index);
        index += 2;

        transfer.symbol = encoded.toBytes32(index);
        index += 32;

        transfer.name = encoded.toBytes32(index);
        index += 32;

        transfer.tokenID = encoded.toUint256(index);
        index += 32;

        transfer.standardID = encoded.toUint16(index);
        index += 2;

        transfer.tokenType = encoded.toUint8(index);
        index += 1;

        length = encoded.toUint16(index);
        index += 2;

        uint256[] memory tokenIDs = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokenIDs[i] = encoded.toUint256(index);
            index += 32;
        }

        transfer.tokenIDs = tokenIDs;

        length = encoded.toUint16(index);
        index += 2;

        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = encoded.toUint256(index);
            index += 32;
        }

        transfer.tokenAmounts = amounts;

        transfer.royaltyAddress = encoded.toBytes32(index);
        index += 32;

        transfer.royaltyBips = encoded.toUint96(index);
        index += 12;

        transfer.rentAddress = encoded.toBytes32(index);
        index += 32;

        transfer.rentExpiryDate = encoded.toUint256(index);
        index += 32;

        length = encoded.toUint16(index);
        index += 2;

        string memory hexStr = encoded.slice(index, length).hexString();
        transfer.uri = hexStr.hexToAscii();
        index += length;

        transfer.to = encoded.toBytes32(index);
        index += 32;

        transfer.toChain = encoded.toUint16(index);
        index += 2;

        length = encoded.toUint16(index);
        index += 2;

        transfer.data = encoded.slice(index, length);
        index += length;

        length = encoded.toUint16(index);
        index += 2;

        transfer.mintData = encoded.slice(index, length);
        index += length;

        //require(encoded.length == index, "invalid Transfer");
    }

    function getBytes() public view returns (bytes memory) {
        // return abi.encodePacked(bytes("0x65e9d8b6069eec1ef3b8bfae57326008b7aec2c900000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000007b00000000000000000000000000000000000000000000000000000000000001c8687474703a2f2f"));
        // return bytes("0x65e9d8b6069eec1ef3b8bfae57326008b7aec2c900000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000007b00000000000000000000000000000000000000000000000000000000000001c8687474703a2f2f");
        return bytes("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
    }

    function getBytesFromString() public view returns (uint) {
        // return abi.encodePacked("https://").length;
        // return uint16(abi.encodePacked("https://").length);
        // return abi.encodePacked("https://remix.ethereum.org/#lang=en&optimize=false&runs=200&evmVersion=null");
        return bytes("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef").length;
    }

    function getStringFromBytes(bytes memory btyeFromStr) public view returns (string memory) {
        return string(btyeFromStr);
    }

    function decodeBytes(bytes memory _bytes) public view returns (string memory) {
        bytes memory encoded = hex"307836356539643862363036396565633165663362386266616535373332363030386237616563326339303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030333030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030323030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030313638373437343730336132663266";
        bytes memory decoded = abi.decode(encoded, (bytes));
        
        return string(decoded);
    }
    
    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function hexToAscii(string memory hexStr) public pure returns (string memory) {
        bytes memory hexBytes = bytes(hexStr);
        bytes memory asciiBytes = new bytes(hexBytes.length / 2);
        uint j = 0;
        for (uint i = 0; i < hexBytes.length; i += 2) {
            uint hexValue = hexToUint(uint8(hexBytes[i])) * 16 + hexToUint(uint8(hexBytes[i+1]));
            asciiBytes[j++] = bytes1(uint8(hexValue));
        }
        return string(asciiBytes);
    }

    function hexToUint(uint8 b) private pure returns (uint) {
        if (b >= uint8(bytes1('0')) && b <= uint8(bytes1('9'))) {
            return uint(b) - uint8(bytes1('0'));
        }
        if (b >= uint8(bytes1('a')) && b <= uint8(bytes1('f'))) {
            return 10 + uint(b) - uint8(bytes1('a'));
        }
        if (b >= uint8(bytes1('A')) && b <= uint8(bytes1('F'))) {
            return 10 + uint(b) - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }

    bytes16 private constant _hexAlphabet = "0123456789abcdef";

    function hexString(bytes memory input) public pure returns (string memory) {
    bytes memory output = new bytes(2 * input.length);

        for (uint i = 0; i < input.length; i++) {
            uint8 b = uint8(input[i]);
            output[2*i] = _hexAlphabet[b >> 4];
            output[2*i+1] = _hexAlphabet[b & 0x0f];
        }

        return string(output);
    }

    struct VM {
		uint8 version;
		uint32 timestamp;
		uint32 nonce;
		uint16 emitterChainId;
		bytes32 emitterAddress;
		uint64 sequence;
		uint8 consistencyLevel;
		bytes payload;

		uint32 guardianSetIndex;
		Signature[] signatures;

		bytes32 hash;
	}

    struct Signature {
		bytes32 r;
		bytes32 s;
		uint8 v;
		uint8 guardianIndex;
	}


    function parseVM(bytes memory encodedVM) public pure virtual returns (VM memory vm) {
        uint index = 0;

        vm.version = encodedVM.toUint8(index);
        index += 1;
        require(vm.version == 1, "VM version incompatible");

        vm.guardianSetIndex = encodedVM.toUint32(index);
        index += 4;

        // Parse Signatures
        uint256 signersLen = encodedVM.toUint8(index);
        index += 1;
        vm.signatures = new Signature[](signersLen);
        for (uint i = 0; i < signersLen; i++) {
            vm.signatures[i].guardianIndex = encodedVM.toUint8(index);
            index += 1;

            vm.signatures[i].r = encodedVM.toBytes32(index);
            index += 32;
            vm.signatures[i].s = encodedVM.toBytes32(index);
            index += 32;
            vm.signatures[i].v = encodedVM.toUint8(index) + 27;
            index += 1;
        }

        // Hash the body
        bytes memory body = encodedVM.slice(index, encodedVM.length - index);
        vm.hash = keccak256(abi.encodePacked(keccak256(body)));

        // Parse the body
        vm.timestamp = encodedVM.toUint32(index);
        index += 4;

        vm.nonce = encodedVM.toUint32(index);
        index += 4;

        vm.emitterChainId = encodedVM.toUint16(index);
        index += 2;

        vm.emitterAddress = encodedVM.toBytes32(index);
        index += 32;

        vm.sequence = encodedVM.toUint64(index);
        index += 8;

        vm.consistencyLevel = encodedVM.toUint8(index);
        index += 1;

        vm.payload = encodedVM.slice(index, encodedVM.length - index);
    }
}
 */
