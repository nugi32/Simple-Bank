// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TimeUtils {
    function _now() internal view returns (uint) { return block.timestamp; }
}