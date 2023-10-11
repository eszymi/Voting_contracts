pragma solidity ^0.8.19;

// utilities
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
// core contracts
import {CheckMerkleProof} from "contracts/utility/CheckMerkleProof.sol";

contract CheckMerkleProofTest is Test {
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    
    CheckMerkleProof mp;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(o1, 10_000 ether);

        // deploying core contract
        vm.prank(o1);
        mp = new CheckMerkleProof();
    }

    function test_MerkleProof() public {
        bytes32 root = 0x490719404157a2be15b6c4efb67103129cdff36f7516fca3d3be19ac190996fd;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xdc270d0f8e135cc414dbbbc2a911a598ed1b0beed34b5d7683beea68b24d6017;
        proof[1] = 0x31378c97985b67e78cf8e374ef49276d6cac5128dc527ea6922440cd0a498ba5;

        uint256 leaf = uint256(keccak256(abi.encodePacked(address(o3)))); 

        bool value = mp.verify(root, bytes32(leaf), proof);
        assertEq(value, true);
    }
}
