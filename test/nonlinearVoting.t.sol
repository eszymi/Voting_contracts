// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// utilities
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// core contracts
import {SnapshotToken} from "contracts/utility/SnapshotToken.sol";
import {NonlinearVoting} from "contracts/NonlinearVoting.sol";
import {VotingWithSnapshotEvents} from "contracts/VotingWithSnapshot.sol";

contract NonlinearVotingTest is Test, VotingWithSnapshotEvents {
    using ECDSA for bytes32;

    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    SnapshotToken token;
    NonlinearVoting voting;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);

        // deploying SnapshotToken + core contract
        vm.prank(admin);
        token = new SnapshotToken('VotingToken','VT');

        vm.prank(admin);
        voting = new NonlinearVoting(address(token), "NonlinearVoting");

        vm.prank(admin);
        token.setSnapshoter(admin);

        // --mint tokens
        address[] memory addresses = new address[](4);
        uint256[] memory amounts = new uint256[](4);

        addresses[0] = o1;
        addresses[1] = o2;
        addresses[2] = o3;
        addresses[3] = o4;
        amounts[0] = 5e18;
        amounts[1] = 10e18;
        amounts[2] = 15e18;
        amounts[3] = 2e18;
        vm.prank(admin);
        token.mintPerUser(addresses, amounts);

        vm.prank(admin);
        token.snapshot();
    }

    function createProposal(uint256 last, uint256 SnapshotID) public {
        vm.prank(admin);
        voting.createProposal("test", last, SnapshotID);
    }

    function vote(address _address, uint256 numberOfProposal, bool choose) public {
        (, uint256 snapshotID,,,) = voting.proposals(numberOfProposal);
        uint256 balance = token.balanceOfAt(_address, snapshotID);

        vm.prank(_address);
        voting.vote(numberOfProposal, balance, choose);
    }

    function calculateRSV(
        address owner,
        string memory name,
        uint256 numberOfProposal,
        uint256 votes,
        bool choose,
        uint256 deadline
    ) public view returns (uint8, bytes32, bytes32, bytes32) {
        uint256 _nonce = voting.nonces(owner) + 1;
        bytes32 digest = keccak256(
            abi.encode(voting.PERMIT_TYPEHASH(), address(owner), numberOfProposal, votes, choose, _nonce, deadline)
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(bytes(name))), digest);
        return (v, r, s, digest);
    }

    function test_Nonlinear1() public {
        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, 100, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, 10);
        assertEq(noCount, 0);
    }

    function test_Nonlinear2() public {
        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, 120, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, 10);
        assertEq(noCount, 0);
    }

    function test_Nonlinear3() public {
        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, 0, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, 0);
        assertEq(noCount, 0);
    }

    function test_PermitVote() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, 3);
        assertEq(noCount, 0);
    }

    function test_Delegate() public {
        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.delegate(o4, 0, 1, 100);

        vm.prank(o4);
        voting.delegateVote(0, 100, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, 10);
        assertEq(noCount, 0);
    }
}
