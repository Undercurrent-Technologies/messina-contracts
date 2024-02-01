// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BridgeStructs.sol";
import "../interfaces/IEscrow.sol";

contract Escrow is ReentrancyGuard, IEscrow {
    address internal bridgeAddress;
    address internal tokenAddress;
    uint256 internal tokenIn = 0;
    uint256 internal tokenOut = 0;
    address internal w1;
    address internal w2;

    constructor(address bridgeAddr, address tokenAddr) {
        bridgeAddress = bridgeAddr;
        tokenAddress = tokenAddr;
        w1 = msg.sender;
        w2 = msg.sender;
    }

    modifier onlyBridge() {
        require(bridgeAddress == msg.sender, "invalid caller");
        _;
    }

    modifier whitelisted() {
        require((w1 == msg.sender) || (w2 == msg.sender), "not whitelisted");
        _;
    }

    function getBridgeAddress() external view override returns (address) {
        return bridgeAddress;
    }

    function amountUpdate(uint256 ain, uint256 aout)
        external
        override
        onlyBridge
    {
        tokenIn = tokenIn + ain;
        tokenOut = tokenOut + aout;
    }

    function deposit(uint256 amount) public whitelisted nonReentrant {
        require(amount > 0, "invalid amount");
        _deposit(msg.sender, amount);
    }

    function _deposit(address sender, uint256 amount) internal virtual {
        // Check user's token balance
        require(
            IERC20(tokenAddress).balanceOf(sender) >= amount,
            "Not enough funds"
        );

        // Do the transfer
        SafeERC20.safeTransferFrom(
            IERC20(tokenAddress),
            sender,
            address(this),
            amount
        );
    }

    function updateBridge(address _bridge)
        external
        override
        onlyBridge
        nonReentrant
    {
        bridgeAddress = _bridge;
    }

    function getWhitelist() public view virtual returns (address[2] memory) {
        return [w1, w2];
    }

    function updateWhitelist(bool w, address _wl)
        external
        override
        onlyBridge
        nonReentrant
    {
        // Update first whitelist if true, else update second whitelist
        if (w) {
            w1 = _wl;
        } else {
            w2 = _wl;
        }
    }

    function transfer(address to, uint256 amount)
        external
        override
        onlyBridge
        nonReentrant
    {
        // Check escrow's balance
        require(
            IERC20(tokenAddress).balanceOf(address(this)) >= amount,
            "Not enough funds"
        );

        // Do the transfer
        SafeERC20.safeTransfer(IERC20(tokenAddress), to, amount);
    }

    function transferEth(address to, uint256 amount)
        external
        override
        onlyBridge
        nonReentrant
    {
        // Check escrow's balance
        require(address(this).balance >= amount, "Not enough funds");

        payable(to).transfer(amount);
    }

    function withdraw(uint256 amount) public whitelisted nonReentrant {
        require(amount > 0, "invalid amount");
        _withdraw(msg.sender, amount);
    }

    function _withdraw(address sender, uint256 amount) internal virtual {
        // Check escrow's balance
        require(
            IERC20(tokenAddress).balanceOf(address(this)) >= amount,
            "Not enough funds"
        );

        // Do the transfer
        SafeERC20.safeTransfer(IERC20(tokenAddress), sender, amount);
    }
}
