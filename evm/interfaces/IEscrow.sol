// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IEscrow {
    function getBridgeAddress() external view returns (address);

    function amountUpdate(uint256 ain, uint256 aout) external;

    function transfer(address to, uint256 amount) external;

    function transferEth(address to, uint256 amount) external;

    function updateBridge(address _bridge) external;

    function updateWhitelist(bool w, address _wl) external;
}
