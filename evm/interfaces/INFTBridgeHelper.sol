// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/CommonStructs.sol";

interface INFTBridgeHelper {
    function encodeTransfer(CommonStructs.Transfer memory transfer)
        external
        pure
        returns (bytes memory);

    function parseTransfer(bytes memory encoded)
        external
        pure
        returns (CommonStructs.Transfer memory transfer);

    // function parseRegisterChain(bytes memory encoded) 
    //     external 
    //     pure 
    //     returns(CommonStructs.RegisterChain memory chain);

    // function parseUpgrade(bytes memory encoded) 
    //     external 
    //     pure 
    //     returns(CommonStructs.UpgradeContract memory chain);
    
    function createWrapped(
        CommonStructs.Transfer memory transfer,
        CommonStructs.NFTInitArgs memory initArgs,
        address beacon721Addr,
        address beacon1155Addr,
        address standardBeaconAddr,
        address bridgeAddr
    ) external returns (uint16, bytes32, address);
}
