// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    function getRandomTier() internal view returns(uint){
        uint num;
        uint a = randomNum(101);

        if(a>=20){
            num = 0;
        } else if (a<20 && a>=5){
            num = 1;
        } else {
            num = 2;
        }

        return num;
    }

    function indexOf(uint256[] memory arr, uint256 searchFor) internal pure returns (int256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == searchFor) {
                return int(i);
            }
        }
        return -1; // not found
    }

    function indexOfAddresses(address[] memory arr, address searchFor) internal pure returns (int256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == searchFor) {
                return int(i);
            }
        }
        return -1; // not found
    }

    function randomNum(uint _mod) internal view returns(uint){
        uint rand;
        rand = uint(keccak256(
           abi.encodePacked(
               block.timestamp, 
               block.difficulty, 
               msg.sender)
            )
        ) % _mod;
        return rand;
    }
}