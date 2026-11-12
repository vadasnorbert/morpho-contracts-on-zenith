// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOracle} from "morpho-blue/interfaces/IOracle.sol";

/// @notice Testnet-only oracle returning an owner-set price.
/// @dev Price of 1 collateral unit in loan units, scaled by 1e36 (Morpho convention).
contract FixedPriceOracle is IOracle {
    address public owner;
    uint256 public price;

    event PriceSet(uint256 price);

    constructor(uint256 initialPrice) {
        owner = msg.sender;
        price = initialPrice;
        emit PriceSet(initialPrice);
    }

    function setPrice(uint256 newPrice) external {
        require(msg.sender == owner, "not owner");
        price = newPrice;
        emit PriceSet(newPrice);
    }
}
