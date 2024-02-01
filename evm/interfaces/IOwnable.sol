// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

/**
 * @dev Interface of the Ownable contract.
 */
interface IOwnable {
    /**
     * @dev Returns the address of the current owner.
     */
    function owner() external view returns (address);

    /**
     * @dev Leaves the contract without owner.
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() external;

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function transferOwnership(address newOwner) external;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
