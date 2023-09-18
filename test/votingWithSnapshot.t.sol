// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// utilities
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// core contracts
import {SnapshotToken} from "contracts/utility/SnapshotToken.sol";
import {VotingWithSnapshot, VotingWithSnapshotEvents} from "contracts/VotingWithSnapshot.sol";

contract SnapshotSimpleVotingTest is Test, VotingWithSnapshotEvents {
    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    SnapshotToken token;
    VotingWithSnapshot voting;

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
        voting = new VotingWithSnapshot(address(token), "VotingWithSnapshot");

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

    function testFail_NotProposer() public {
        vm.prank(o4);
        voting.createProposal("test", VOTING_PERIOD, 1);
    }

    function test_Proposer() public {
        vm.expectEmit(true, false, false, true);
        emit NowProposal(0, VOTING_PERIOD, 1);

        createProposal(VOTING_PERIOD, 1);
    }

    function test_vote() public {
        createProposal(VOTING_PERIOD, 1);

        vote(o1, 0, true);
        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);

        assertGt(yesCount, 0);
        assertEq(noCount, 0);
    }

    function test_CreateMoreProposals() public {
        vm.expectEmit(true, false, false, true);
        emit NowProposal(0, VOTING_PERIOD, 1);

        createProposal(VOTING_PERIOD, 1);

        vm.expectEmit(true, false, false, true);
        emit NowProposal(1, VOTING_PERIOD, 2);

        createProposal(VOTING_PERIOD, 2);
    }

    function testFail_ResultBeforeEnd() public {
        createProposal(VOTING_PERIOD, 1);

        voting.result(0);
    }

    function testFuzz_NoResultEmitted(bool value) public {
        createProposal(VOTING_PERIOD, 1);

        vote(o1, 0, value);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.expectEmit(true, false, false, true);
        emit NoResult(0);

        voting.result(0);
    }

    function testFuzz_ResultEmitted(bool value) public {
        createProposal(VOTING_PERIOD, 1);

        vote(o1, 0, value);
        vote(o3, 0, value);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.expectEmit(true, true, false, true);
        emit Result(0, value);

        voting.result(0);
    }
}

contract SnapshotDelegateVotingTest is Test, VotingWithSnapshotEvents {
    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address o5 = makeAddr("o5");
    address admin = makeAddr("admin");

    SnapshotToken token;
    VotingWithSnapshot voting;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);
        vm.deal(o5, 10_000 ether);

        // deploying SnapshotToken + core contract
        vm.prank(admin);
        token = new SnapshotToken('VotingToken','VT');

        vm.prank(admin);
        voting = new VotingWithSnapshot(address(token), "VotingWithSnapshot");

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

    function delegate(address from, address to, uint256 snapshotID, uint256 numberOfProposal) public {
        uint256 balance = token.balanceOfAt(from, snapshotID);

        vm.prank(from);
        voting.delegate(to, numberOfProposal, snapshotID, balance);
    }

    function test_ChangeProposer() public {
        vm.expectEmit(true, true, false, true);
        emit NewProposer(admin, o4);

        vm.prank(admin);
        voting.changeProposer(o4);
    }

    function testFail_RejectChangeProposal(address _address) public {
        vm.assume(_address != admin);

        vm.prank(_address);
        voting.changeProposer(o4);
    }

    function test_Delegate(address _address) public {
        uint256 balance = token.balanceOfAt(o1, 1);

        vm.expectEmit(true, true, true, true);
        emit Delegated(o1, _address, 0, 1, balance);

        delegate(o1, _address, 1, 0);
    }

    function test_DelegateVoteAtOnce() public {
        uint256 balance = token.balanceOfAt(o1, 1);
        delegate(o1, o5, 1, 0);

        createProposal(VOTING_PERIOD, 1);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance, true);

        vm.prank(o5);
        voting.delegateVote(0, balance, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance);
        assertEq(noCount, 0);
    }

    function test_DelegateVoteNotOnce() public {
        uint256 balance = token.balanceOfAt(o1, 1);
        delegate(o1, o5, 1, 0);

        createProposal(VOTING_PERIOD, 1);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance / 2, true);

        vm.prank(o5);
        voting.delegateVote(0, balance / 2, true);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance / 2, false);

        vm.prank(o5);
        voting.delegateVote(0, balance / 2, false);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance / 2);
        assertEq(noCount, balance / 2);
    }

    function test_VoteAndDelegateVote() public {
        uint256 balanceO1 = token.balanceOfAt(o1, 1);
        delegate(o1, o4, 1, 0);

        createProposal(VOTING_PERIOD, 1);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o4, balanceO1, true);

        vm.prank(o4);
        voting.delegateVote(0, balanceO1, true);

        uint256 balanceO4 = token.balanceOfAt(o4, 1);

        vm.expectEmit(true, true, false, true);
        emit Voted(0, o4, balanceO4, false);

        vote(o4, 0, false);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balanceO1);
        assertEq(noCount, balanceO4);
    }

    function test_FewAccountsDelegateOneAccount() public {
        uint256 balanceO1 = token.balanceOfAt(o1, 1);
        uint256 balanceO2 = token.balanceOfAt(o2, 1);
        delegate(o1, o5, 1, 0);
        delegate(o2, o5, 1, 0);

        createProposal(VOTING_PERIOD, 1);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balanceO1 + balanceO2, true);

        vm.prank(o5);
        voting.delegateVote(0, balanceO1 + balanceO2, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balanceO1 + balanceO2);
        assertEq(noCount, 0);
    }
}

contract SnapshotPermitVotingTest is Test, VotingWithSnapshotEvents {
    using ECDSA for bytes32;

    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    SnapshotToken token;
    VotingWithSnapshot voting;

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
        voting = new VotingWithSnapshot(address(token), "VotingWithSnapshot");

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

    function test_RSV() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_OwnerIsNotSigner() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_DeadlineExpired() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        vm.warp(101);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_MultiuseSameHash() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_UseSygnatureToOtherProposal() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        createProposal(VOTING_PERIOD, 1);

        voting.permitVote(o1, 1, 10, true, 100, digest, v, r, s);
    }

    function testFail_DelegateByPermitMoreTokens() public {
        uint256 balance = token.balanceOfAt(o1, 1);
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, balance, true, 100);

        voting.permitVote(o1, 0, balance, true, 100, digest, v, r, s);
    }
}

contract SnapshotSnapshotVotingTest is Test, VotingWithSnapshotEvents {
    using ECDSA for bytes32;

    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    SnapshotToken token;
    VotingWithSnapshot voting;

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
        voting = new VotingWithSnapshot(address(token), "VotingWithSnapshot");

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

    function test_VoteWithTokensFromOldSnapshot() public {
        uint256 balance = token.balanceOfAt(o1, 1);

        vm.prank(o1);
        token.transfer(o2, balance / 2);

        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, balance, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance);
        assertEq(noCount, 0);
    }

    function testFail_VoteTokensFromNotCorrectSnapshot() public {
        uint256 balance01 = token.balanceOfAt(o1, 1);

        vm.prank(o1);
        token.transfer(o2, balance01 / 2);

        vm.prank(admin);
        token.snapshot();

        createProposal(VOTING_PERIOD, 1);

        uint256 balance02 = token.balanceOfAt(o2, 2);

        assertGt(balance02, balance01);

        vm.prank(o2);
        voting.vote(0, balance02, true);
    }

    function test_VoteTokensFromNewSnapshot() public {
        uint256 balance01 = token.balanceOfAt(o1, 1);

        vm.prank(o1);
        token.transfer(o2, balance01 / 2);

        vm.prank(admin);
        token.snapshot();

        createProposal(VOTING_PERIOD, 2);

        uint256 balance02 = token.balanceOfAt(o2, 2);

        assertGt(balance02, balance01);

        vm.prank(o2);
        voting.vote(0, balance02, true);

        (,,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance02);
        assertEq(noCount, 0);
    }

    function testFail_CanVoteTwiceToTheSameProposal() public {
        uint256 balance = token.balanceOfAt(o1, 1);

        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, balance, true);

        vm.prank(o1);
        voting.vote(0, balance, true);
    }

    function testFail_CanVoteAndPermitVoteToTheSameProposal() public {
        uint256 balance = token.balanceOfAt(o1, 1);

        createProposal(VOTING_PERIOD, 1);

        vm.prank(o1);
        voting.vote(0, balance, true);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_CanPermitVoteTwiceToTheSameProposal() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);

        (uint8 v1, bytes32 r1, bytes32 s1, bytes32 digest1) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest1, v1, r1, s1);
    }

    function testFail_CanDelegateAndVoteToTheSameProposal() public {
        createProposal(VOTING_PERIOD, 1);

        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);

        vm.prank(o1);
        voting.delegate(o2, 0, 1, 100);
    }

    function test_VoteToDifferentProposal() public {
        uint256 balance = token.balanceOfAt(o1, 1);
        createProposal(VOTING_PERIOD, 1);
        createProposal(VOTING_PERIOD, 1);

        vote(o1, 0, true);
        vote(o1, 1, false);

        (,,, uint256 yesCount0, uint256 noCount0) = voting.proposals(0);
        assertEq(yesCount0, balance);
        assertEq(noCount0, 0);

        (,,, uint256 yesCount1, uint256 noCount1) = voting.proposals(1);
        assertEq(yesCount1, 0);
        assertEq(noCount1, balance);
    }
}
