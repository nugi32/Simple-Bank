// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library regular {
    function greater_than_0(uint num) internal pure {
        require(num > 0, "Must be greater than 0 !");
    }
}