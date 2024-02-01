// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/external/BytesLib.sol";

import "./BridgeGetters.sol";
import "./BridgeSetters.sol";
import "./BridgeStructs.sol";
import "./BridgeGovernance.sol";

import "./token/Token.sol";
import "./token/TokenImplementation.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IWormhole.sol";

contract Bridge is BridgeGovernance, ReentrancyGuard {
    using BytesLib for bytes;

    struct ParseAndVerifyVMResults {
        IWormhole.VM vm;
        bool valid;
        string reason;
    }

    struct AttestTokenInfo {
        bytes queriedDecimals;
        bytes queriedSymbol;
        bytes queriedName;
        uint8 decimals;
    }
    
    modifier whenNotPaused() {
        require(!isPaused(), "contract paused");
        _;
    }

    function updateEscrow(address _escrow, address _bridge) public onlyOwner {
        IEscrow(_escrow).updateBridge(_bridge);
    }

    function updateWhitelist(address _escrow, bool w, address _wl) public onlyOwner {
        IEscrow(_escrow).updateWhitelist(w, _wl);
    }

    // Produce a AssetMeta message for a given token
    function attestToken(address tokenAddress, uint32 nonce, BridgeStructs.TokenConfig memory config, string memory network) public payable onlyOwner {
        AttestTokenInfo memory attestTokenInfo;
        // decimals, symbol & token are not part of the core ERC20 token standard, so we need to support contracts that dont implement them
        (, attestTokenInfo.queriedDecimals) = tokenAddress.staticcall(abi.encodeWithSignature("decimals()"));
        (, attestTokenInfo.queriedSymbol) = tokenAddress.staticcall(abi.encodeWithSignature("symbol()"));
        (, attestTokenInfo.queriedName) = tokenAddress.staticcall(abi.encodeWithSignature("name()"));

        attestTokenInfo.decimals = abi.decode(attestTokenInfo.queriedDecimals, (uint8));

        string memory symbolString = abi.decode(attestTokenInfo.queriedSymbol, (string));
        string memory nameString = abi.decode(attestTokenInfo.queriedName, (string));

        bytes32 symbol;
        bytes32 name;
        assembly {
            // first 32 bytes hold string length
            symbol := mload(add(symbolString, 32))
            name := mload(add(nameString, 32))
        }

        BridgeStructs.AssetMeta memory meta = BridgeStructs.AssetMeta({
        payloadID : 2,
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        tokenAddress : bytes32(uint256(uint160(tokenAddress))),
        // Chain ID of the token
        tokenChain : chainId(),
        // Number of decimals of the token (big-endian uint8)
        decimals : attestTokenInfo.decimals,
        // Symbol of the token (UTF-8)
        symbol : symbol,
        // Name of the token (UTF-8)
        name : name
        });

        require(tokenConfig(tokenAddress).Escrow == address(0), "asset already exists");

        // The escrow pointing the correct bridge?
        require(IEscrow(config.Escrow).getBridgeAddress() == address(this), "invalid escrow bridge address");
        // Set token config
        setTokenConfig(tokenAddress, config);

        bytes memory encoded = encodeAssetMeta(meta);   

        Router().publishMessage{value: msg.value}(network, msg.value, nonce, encoded, finality());
    }

    function wrapAndTransferETH(uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce, string memory network) public payable whenNotPaused {
        BridgeStructs.TransferResult memory transferResult = _wrapAndTransferETH(arbiterFee, network);
        logTransfer(transferResult.tokenChain, transferResult.tokenAddress, transferResult.normalizedAmount, recipientChain, recipient, transferResult.normalizedArbiterFee, transferResult.wormholeFee, nonce, network);
    }

    function wrapAndTransferETHWithPayload(uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce, bytes memory payload, string memory network) public payable whenNotPaused {
        BridgeStructs.TransferResult memory transferResult = _wrapAndTransferETH(arbiterFee, network);
        logTransferWithPayload(transferResult.tokenChain, transferResult.tokenAddress, transferResult.normalizedAmount, recipientChain, recipient, transferResult.normalizedArbiterFee, transferResult.wormholeFee, nonce, payload, network);
    }

    function _wrapAndTransferETH(uint256 arbiterFee, string memory network) internal returns (BridgeStructs.TransferResult memory transferResult) {
        uint wormholeFee = Router().messageFee(network);
        uint platformFee = getPlatformFeesAmount(msg.value, tokenConfig(address(WETH())).transferFee, 18);
        uint fees = wormholeFee + platformFee;
        uint16 tokenChain;
        bytes32 tokenAddress;

        if (isWrappedAsset(address(WETH()))) {
            tokenChain = _state.wrapperTracker[address(WETH())].chainId;
            tokenAddress = _state.wrapperTracker[address(WETH())].assetAddress;
        } else {
            tokenChain = chainId();
            tokenAddress = bytes32(uint256(uint160(address(WETH()))));
        }

        require(fees < msg.value, "amount lower than fees");

        uint amount = msg.value - fees;

        require(arbiterFee <= amount, "arbiter fee too high");

        uint normalizedAmount = normalizeAmount(amount, 18);
        uint normalizedArbiterFee = normalizeAmount(arbiterFee, 18);

        // refund dust
        uint dust = amount - deNormalizeAmount(normalizedAmount, 18);
        if (dust > 0) {
            payable(msg.sender).transfer(dust);
        }

        amount = msg.value - dust;
        BridgeStructs.TokenConfig memory currentTokenConfig = tokenConfig(address(WETH()));
        require(currentTokenConfig.max >= amount && currentTokenConfig.min <= amount, 'amount not Valid');

        // deposit into WETH
        WETH().deposit{
            value : amount
        }();

        // amount minus platform fee (if any)
        if (platformFee > 0) {
            amount = amount - fees;
            SafeERC20.safeTransferFrom(WETH(), address(this), getTreasury(), fees);
        }

        address escrow = currentTokenConfig.Escrow;
        SafeERC20.safeTransferFrom(WETH(), address(this), escrow, amount);
        IEscrow(escrow).amountUpdate(amount, uint256(0));

        transferResult = BridgeStructs.TransferResult({
            tokenChain : tokenChain,
            tokenAddress : tokenAddress,
            normalizedAmount : normalizedAmount,
            normalizedArbiterFee : normalizedArbiterFee,
            wormholeFee : wormholeFee,
            platformFee : platformFee
        });
    }

    function transferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce, string memory network) public payable nonReentrant whenNotPaused {
        BridgeStructs.TransferResult memory transferResult = _transferTokens(token, amount, arbiterFee);
        logTransfer(transferResult.tokenChain, transferResult.tokenAddress, transferResult.normalizedAmount, recipientChain, recipient, transferResult.normalizedArbiterFee, transferResult.wormholeFee, nonce, network);
    }

    function transferTokensWithPayload(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce, bytes memory payload, string memory network) public payable nonReentrant whenNotPaused {
        BridgeStructs.TransferResult memory transferResult = _transferTokens(token, amount, arbiterFee);
        logTransferWithPayload(transferResult.tokenChain, transferResult.tokenAddress, transferResult.normalizedAmount, recipientChain, recipient, transferResult.normalizedArbiterFee, transferResult.wormholeFee, nonce, payload, network);
    }

    // Initiate a Transfer
    function _transferTokens(address token, uint256 amount, uint256 arbiterFee) internal returns (BridgeStructs.TransferResult memory transferResult) {
        BridgeStructs.TokenConfig memory currentTokenConfig = tokenConfig(token);
        require(currentTokenConfig.max>=amount && currentTokenConfig.min <= amount,'amount not Valid');
        // determine token parameters
        uint16 tokenChain;
        bytes32 tokenAddress;
        
        if (isWrappedAsset(token)) {
            tokenChain = _state.wrapperTracker[token].chainId;
            tokenAddress = _state.wrapperTracker[token].assetAddress;
        } else {
            tokenChain = chainId();
            tokenAddress = bytes32(uint256(uint160(token)));
        }

        // query tokens decimals
        (,bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);
        // cut the platform fee from the recived amount

        uint platformFee;
        if (currentTokenConfig.src || currentTokenConfig.transferFee > 0) {
            platformFee = getPlatformFeesAmount(amount, currentTokenConfig.transferFee, decimals);
        } 

        address escrow = currentTokenConfig.Escrow;

        // amount minus platform fee (if any)
        if (platformFee > 0) {
            amount = amount - platformFee;
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, getTreasury(), platformFee);
        }

        if (tokenChain == chainId()) {
            // query own token balance before transfer
            (,bytes memory queriedBalanceBefore) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, escrow));
            uint256 balanceBefore = abi.decode(queriedBalanceBefore, (uint256));

            // transfer tokens
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, escrow, amount);

            // query own token balance after transfer
            (,bytes memory queriedBalanceAfter) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, escrow));
            uint256 balanceAfter = abi.decode(queriedBalanceAfter, (uint256));

            // correct amount for potential transfer fees
            amount = balanceAfter - balanceBefore;
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, escrow, amount);
        }

        IEscrow(escrow).amountUpdate(amount, uint256(0));

        // normalize amounts decimals
        uint256 normalizedAmount = normalizeAmount(amount, decimals);
        uint256 normalizedArbiterFee = normalizeAmount(arbiterFee, decimals);

        transferResult = BridgeStructs.TransferResult({
            tokenChain : tokenChain,
            tokenAddress : tokenAddress,
            normalizedAmount : normalizedAmount,
            normalizedArbiterFee : normalizedArbiterFee,
            wormholeFee : msg.value,
            platformFee: platformFee
        });
    }
    
    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256) {
        amount = (amount * 100000000) / (10 ** decimals);
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256) {
        amount = ((amount * (10 ** decimals)) / 100000000)  ;
        return amount;
    }

    function logTransfer(uint16 tokenChain, bytes32 tokenAddress, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 fee, uint256 callValue, uint32 nonce, string memory network) internal {
        require(fee <= amount, "fee exceeds amount");

        BridgeStructs.Transfer memory transfer = BridgeStructs.Transfer({
            payloadID : 1,
            amount : amount,
            tokenAddress : tokenAddress,
            tokenChain : tokenChain,
            to : recipient,
            toChain : recipientChain,
            fee : fee
        });

        bytes memory encoded = encodeTransfer(transfer);
        
        Router().publishMessage{value: callValue}(network, callValue, nonce, encoded, finality());
    }

    function logTransferWithPayload(uint16 tokenChain, bytes32 tokenAddress, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 fee, uint256 callValue, uint32 nonce, bytes memory payload, string memory network) internal {
        require(fee <= amount, "fee exceeds amount");

        BridgeStructs.TransferWithPayload memory transfer = BridgeStructs.TransferWithPayload({
            payloadID : 3,
            amount : amount,
            tokenAddress : tokenAddress,
            tokenChain : tokenChain,
            to : recipient,
            toChain : recipientChain,
            fee : fee,
            payload : payload
        });

        bytes memory encoded = encodeTransferWithPayload(transfer);

        Router().publishMessage{value: callValue}(network, callValue, nonce, encoded, finality());
    }

    function updateAttested(bytes memory encodedVm, address wrapperToken, BridgeStructs.TokenConfig memory config, string memory network) onlyOwner external {

        (IWormhole.VM memory vm, bool valid, string memory reason) = Router().parseAndVerifyVM(network, encodedVm);

        require(valid, reason);
        require(verifyBridgeVM(vm), "invalid emitter");

        BridgeStructs.AssetMeta memory meta = parseAssetMeta(vm.payload);
        return _updateAttested(meta, wrapperToken, config);
    }

    function _updateAttested(BridgeStructs.AssetMeta memory meta, address wrapperToken, BridgeStructs.TokenConfig memory config) internal {
        address wrapped = wrappedAsset(meta.tokenChain, meta.tokenAddress);
        require(wrapped != address(0), "wrapped asset does not exists");

        // The escrow pointing the correct bridge?
        require(IEscrow(config.Escrow).getBridgeAddress() == address(this), "invalid escrow bridge address");

        setWrappedAsset(meta.tokenChain, meta.tokenAddress, wrapperToken);
        setTokenConfig(wrapperToken, config);
    }

    function receiveAttest(bytes memory encodedVm, address wrapperToken, BridgeStructs.TokenConfig memory config, string memory network) onlyOwner external {

        (IWormhole.VM memory vm, bool valid, string memory reason) = Router().parseAndVerifyVM(network, encodedVm);

        require(valid, reason);
        require(verifyBridgeVM(vm), "invalid emitter");

        BridgeStructs.AssetMeta memory meta = parseAssetMeta(vm.payload);
        return _receiveAttest(meta, wrapperToken, config);
    }

    // Creates a wrapped asset using AssetMeta
    function _receiveAttest(BridgeStructs.AssetMeta memory meta, address wrapperToken, BridgeStructs.TokenConfig memory config) internal {
        require(meta.tokenChain != chainId(), "can only wrap tokens from foreign chains");
        require(wrappedAsset(meta.tokenChain, meta.tokenAddress) == address(0), "wrapped asset already exists");

        setWrappedAsset(meta.tokenChain, meta.tokenAddress, wrapperToken);

        // THe escrow pointing the correct bridge?
        require(IEscrow(config.Escrow).getBridgeAddress() == address(this), "invalid escrow bridge address");
        setTokenConfig(wrapperToken, config);
    }

    function completeTransferWithPayload(bytes memory encodedVm, address feeRecipient, string memory network) public whenNotPaused returns (bytes memory) {
        return _completeTransfer(encodedVm, feeRecipient, network);
    }


    function completeTransfer(bytes memory encodedVm, string memory network) public whenNotPaused {
        _completeTransfer(encodedVm, msg.sender, network);
    }

    // Execute a Transfer message
    function _completeTransfer(bytes memory encodedVm, address feeRecipient, string memory network) internal returns (bytes memory) {
        ParseAndVerifyVMResults memory parseAndVerifyVMResults;

        (parseAndVerifyVMResults.vm, parseAndVerifyVMResults.valid, parseAndVerifyVMResults.reason) = Router().parseAndVerifyVM(network, encodedVm);

        require(parseAndVerifyVMResults.valid, parseAndVerifyVMResults.reason);
        require(verifyBridgeVM(parseAndVerifyVMResults.vm), "invalid emitter");

        BridgeStructs.Transfer memory transfer = parseTransfer(parseAndVerifyVMResults.vm.payload);

        // payload 3 must be redeemed by the designated proxy contract
        address transferRecipient = address(uint160(uint256(transfer.to)));
        if (transfer.payloadID == 3) {
            require(msg.sender == transferRecipient, "invalid sender");
        }

        require(!isTransferCompleted(parseAndVerifyVMResults.vm.hash), "transfer already completed");
        setTransferCompleted(parseAndVerifyVMResults.vm.hash);

        require(transfer.toChain == chainId(), "invalid target chain");

        IERC20 transferToken;
        if (transfer.tokenChain == chainId()) {
            transferToken = IERC20(address(uint160(uint256(transfer.tokenAddress))));
        } else {
            address wrapped = wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
            require(wrapped != address(0), "no wrapper for this token created yet");

            transferToken = IERC20(wrapped);
        }

        // query decimals
        (,bytes memory queriedDecimals) = address(transferToken).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // adjust decimals
        uint256 nativeAmount = deNormalizeAmount(transfer.amount, decimals);
        uint256 nativeFee = deNormalizeAmount(transfer.fee, decimals);

        BridgeStructs.TokenConfig memory currentTokenConfig = tokenConfig(address(transferToken));

        require(currentTokenConfig.max >= nativeAmount, 'amount not Valid');

        address escrow = currentTokenConfig.Escrow;

        // transfer fee to arbiter
        if (nativeFee > 0 && transferRecipient != feeRecipient) {
            require(nativeFee <= nativeAmount, "fee higher than transferred amount");

            IEscrow(escrow).transfer(feeRecipient, nativeFee);
            
        } else {
            // set fee to zero in case transferRecipient == feeRecipient
            nativeFee = 0;
        }

        // transfer bridged amount to recipient
        uint transferAmount = nativeAmount - nativeFee;

        uint platformfee;
        if (currentTokenConfig.dest || currentTokenConfig.redeemFee > 0) {
            platformfee = getPlatformFeesAmount(nativeAmount, currentTokenConfig.redeemFee, decimals);
        }
        
        if (platformfee > 0) {
            IEscrow(escrow).transfer(getTreasury(),  platformfee);
        }

        IEscrow(escrow).amountUpdate(uint256(0), (transferAmount - platformfee));

        IEscrow(escrow).transfer(transferRecipient, (transferAmount - platformfee));

        return parseAndVerifyVMResults.vm.payload;
    }

    function verifyBridgeVM(IWormhole.VM memory vm) internal view returns (bool){
        if (bridgeContracts(vm.emitterChainId) == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function setTokenConfig(
        address tokenAddress,
        BridgeStructs.TokenConfig memory newConf
    ) public onlyOwner {
        require(tokenAddress != address(0), "invalid Token Address");
        require((newConf.max != 0 || newConf.min <= newConf.max), "invalid min/max configuration");
        setTokenConfiguration(tokenAddress, newConf);
    }

    function encodeAssetMeta(BridgeStructs.AssetMeta memory meta) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            meta.payloadID,
            meta.tokenAddress,
            meta.tokenChain,
            meta.decimals,
            meta.symbol,
            meta.name
        );
    }

    function encodeTransfer(BridgeStructs.Transfer memory transfer) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            transfer.payloadID,
            transfer.amount,
            transfer.tokenAddress,
            transfer.tokenChain,
            transfer.to,
            transfer.toChain,
            transfer.fee
        );
    }

    function encodeTransferWithPayload(BridgeStructs.TransferWithPayload memory transfer) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            transfer.payloadID,
            transfer.amount,
            transfer.tokenAddress,
            transfer.tokenChain,
            transfer.to,
            transfer.toChain,
            transfer.fee,
            transfer.payload
        );
    }

    function parseAssetMeta(bytes memory encoded) public pure returns (BridgeStructs.AssetMeta memory meta) {
        uint index = 0;

        meta.payloadID = encoded.toUint8(index);
        index += 1;

        require(meta.payloadID == 2, "invalid AssetMeta");

        meta.tokenAddress = encoded.toBytes32(index);
        index += 32;

        meta.tokenChain = encoded.toUint16(index);
        index += 2;

        meta.decimals = encoded.toUint8(index);
        index += 1;

        meta.symbol = encoded.toBytes32(index);
        index += 32;

        meta.name = encoded.toBytes32(index);
        index += 32;

        require(encoded.length == index, "invalid AssetMeta");
    }

    function parseTransfer(bytes memory encoded) public pure returns (BridgeStructs.Transfer memory transfer) {
        uint index = 0;

        transfer.payloadID = encoded.toUint8(index);
        index += 1;

        require(transfer.payloadID == 1 || transfer.payloadID == 3, "invalid Transfer");

        transfer.amount = encoded.toUint256(index);
        index += 32;

        transfer.tokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.tokenChain = encoded.toUint16(index);
        index += 2;

        transfer.to = encoded.toBytes32(index);
        index += 32;

        transfer.toChain = encoded.toUint16(index);
        index += 2;

        transfer.fee = encoded.toUint256(index);
        index += 32;

        // payload 3 allows for an arbitrary additional payload
        require(encoded.length == index || transfer.payloadID == 3, "invalid Transfer");
    }

    function getPlatformFeesAmount(uint amount, uint256 platformFee, uint8 decimals) public pure returns (uint) {
        return deNormalizeAmount(normalizeAmount(((amount * platformFee) / 10000000000), decimals), decimals);
    }

    // we need to accept ETH sends to unwrap WETH
    receive() external payable {}
}