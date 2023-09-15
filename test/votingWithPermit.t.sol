// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// utilities
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// core contracts
import {PermitToken} from "contracts/utility/PermitToken.sol";
import {VotingWithPermit, VotingWithPermitEvents} from "contracts/VotingWithPermit.sol";

// check back compatible be this contract
contract SimpleVotingTest is Test, VotingWithPermitEvents {
    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    PermitToken token;
    VotingWithPermit voting;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);

        // deploying PermitToken + core contract
        vm.prank(admin);
        token = new PermitToken('VotingToken','VT');

        vm.prank(admin);
        voting = new VotingWithPermit(address(token), "Voting With Permit");

        vm.prank(admin);
        token.setDelegater(address(voting));

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
    }

    function createProposal(uint256 last) public {
        vm.prank(admin);
        voting.createProposal("test", last);
    }

    function vote(address _address, uint256 numberOfProposal, bool _votes) public {
        uint256 balance = token.balanceOf(_address);

        vm.prank(_address);
        token.approve(address(voting), type(uint256).max);

        vm.prank(_address);
        voting.vote(numberOfProposal, balance, _votes);
    }

    function testFail_NotProposer() public {
        vm.prank(o4);
        voting.createProposal("test", VOTING_PERIOD);
    }

    function test_Proposer() public {
        vm.expectEmit(true, false, false, true);
        emit NowProposal(0, VOTING_PERIOD);

        createProposal(VOTING_PERIOD);
    }

    function test_vote() public {
        createProposal(VOTING_PERIOD);

        vote(o1, 0, true);
        (,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertGt(yesCount, 0);
        assertEq(noCount, 0);
    }

    function test_CreateMoreProposals() public {
        vm.expectEmit(true, false, false, true);
        emit NowProposal(0, VOTING_PERIOD);

        createProposal(VOTING_PERIOD);

        vm.expectEmit(true, false, false, true);
        emit NowProposal(1, VOTING_PERIOD);

        createProposal(VOTING_PERIOD);
    }

    function test_Withdraw() public {
        uint256 balanceBefore = token.balanceOf(o3);

        createProposal(VOTING_PERIOD);

        vote(o3, 0, true);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        uint256 balance = token.balanceOf(o3);
        assertEq(balance, 0);

        vm.prank(o3);
        voting.withdraw(0);

        uint256 balanceAfter = token.balanceOf(o3);
        assertEq(balanceBefore, balanceAfter);
        assertGt(balanceAfter, 0);
    }

    function testFail_WithdrawBeforeEnd() public {
        createProposal(VOTING_PERIOD);

        vm.prank(o3);
        voting.withdraw(0);
    }

    function testFail_ResultBeforeEnd() public {
        createProposal(VOTING_PERIOD);

        voting.result(0);
    }

    function testFuzz_NoResultEmitted(bool value) public {
        createProposal(VOTING_PERIOD);

        vote(o1, 0, value);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.expectEmit(true, false, false, true);
        emit NoResult(0);

        voting.result(0);
    }

    function testFuzz_ResultEmitted(bool value) public {
        createProposal(VOTING_PERIOD);

        vote(o1, 0, value);
        vote(o3, 0, value);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.expectEmit(true, true, false, true);
        emit Result(0, value);

        voting.result(0);
    }
}

// check back compatible with Delegate
contract DelegateVotingTest is Test, VotingWithPermitEvents {
    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address o5 = makeAddr("o5");
    address admin = makeAddr("admin");

    PermitToken token;
    VotingWithPermit voting;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);
        vm.deal(o5, 10_000 ether);

        // deploying token + core contract
        vm.prank(admin);
        token = new PermitToken('VotingToken','VT');

        vm.prank(admin);
        voting = new VotingWithPermit(address(token), "Voting With Permit");

        vm.prank(admin);
        token.setDelegater(address(voting));

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
    }

    function createProposal(uint256 last) public {
        vm.prank(admin);
        voting.createProposal("test", last);
    }

    function vote(address _address, uint256 numberOfProposal, bool _value) public {
        uint256 balance = token.balanceOf(_address);

        vm.prank(_address);
        token.approve(address(voting), type(uint256).max);

        vm.prank(_address);
        voting.vote(numberOfProposal, balance, _value);
    }

    function delegate(address from, address to, uint256 numberOfProposal) public {
        uint256 balance = token.balanceOf(from);

        vm.prank(from);
        token.approve(address(voting), type(uint256).max);

        vm.prank(from);
        voting.delegate(to, numberOfProposal, balance);
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
        uint256 balance = token.balanceOf(o1);

        vm.expectEmit(true, true, true, true);
        emit Delegated(o1, _address, 0, balance);

        delegate(o1, _address, 0);
    }

    function test_DelegateVoteAtOnce() public {
        uint256 balance = token.balanceOf(o1);
        delegate(o1, o5, 0);

        createProposal(VOTING_PERIOD);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance, true);

        vm.prank(o5);
        voting.delegateVote(0, balance, true);

        (,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance);
        assertEq(noCount, 0);
    }

    function test_DelegateVoteNotOnce() public {
        uint256 balance = token.balanceOf(o1);
        delegate(o1, o5, 0);

        createProposal(VOTING_PERIOD);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance / 2, true);

        vm.prank(o5);
        voting.delegateVote(0, balance / 2, true);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balance / 2, true);

        vm.prank(o5);
        voting.delegateVote(0, balance / 2, true);

        (,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balance);
        assertEq(noCount, 0);
    }

    function test_VoteAndDelegateVote() public {
        uint256 balanceO1 = token.balanceOf(o1);
        delegate(o1, o4, 0);

        createProposal(VOTING_PERIOD);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o4, balanceO1, true);

        vm.prank(o4);
        voting.delegateVote(0, balanceO1, true);

        uint256 balanceO4 = token.balanceOf(o4);

        vm.expectEmit(true, true, false, true);
        emit Voted(0, o4, balanceO4, false);

        vote(o4, 0, false);

        (,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balanceO1);
        assertEq(noCount, balanceO4);
    }

    function testFail_WithdrawAfterDelegateBeforeDeadline() public {
        delegate(o1, o4, 0);

        createProposal(VOTING_PERIOD);

        vm.prank(o1);
        voting.withdraw(0);
    }

    function test_WithdrawDelegate() public {
        uint256 balance = token.balanceOf(o1);
        delegate(o1, o4, 0);

        createProposal(VOTING_PERIOD);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(o1);
        voting.withdraw(0);

        assertEq(balance, token.balanceOf(o1));
    }

    function test_WithdrawDelegate2() public {
        uint256 balance = token.balanceOf(o1);
        delegate(o1, o4, 0);

        createProposal(VOTING_PERIOD);

        vm.prank(o4);
        voting.delegateVote(0, balance, true);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(o1);
        voting.withdraw(0);

        assertEq(balance, token.balanceOf(o1));
    }

    function test_FewAccountDelegateOneAccount() public {
        uint256 balanceO1 = token.balanceOf(o1);
        uint256 balanceO2 = token.balanceOf(o2);
        delegate(o1, o5, 0);
        delegate(o2, o5, 0);

        createProposal(VOTING_PERIOD);

        vm.expectEmit(true, true, false, true);
        emit DelegateVoted(0, o5, balanceO1 + balanceO2, true);

        vm.prank(o5);
        voting.delegateVote(0, balanceO1 + balanceO2, true);

        (,, uint256 yesCount, uint256 noCount) = voting.proposals(0);
        assertEq(yesCount, balanceO1 + balanceO2);
        assertEq(noCount, 0);

        vm.roll(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(o1);
        voting.withdraw(0);

        assertEq(balanceO1, token.balanceOf(o1));

        vm.prank(o2);
        voting.withdraw(0);

        assertEq(balanceO2, token.balanceOf(o2));
    }
}

contract PermitVotingTest is Test, VotingWithPermitEvents {
    using ECDSA for bytes32;

    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address o5 = makeAddr("o5");
    address admin = makeAddr("admin");

    PermitToken token;
    VotingWithPermit voting;

    mapping(address => uint256) privateKeyMapping;

    /// preliminary state
    function setUp() public {
        privateKeyMapping[o1] = uint256(keccak256(bytes("o1")));
        privateKeyMapping[o2] = uint256(keccak256(bytes("o2")));
        privateKeyMapping[o3] = uint256(keccak256(bytes("o3")));
        privateKeyMapping[o4] = uint256(keccak256(bytes("o4")));

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);
        vm.deal(o5, 10_000 ether);

        // deploying token + core contract
        vm.prank(admin);
        token = new PermitToken('VotingToken','VT');

        vm.prank(admin);
        voting = new VotingWithPermit(address(token), "Voting With Permit");

        vm.prank(admin);
        token.setDelegater(address(voting));

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

        createProposal(VOTING_PERIOD);
    }

    function createProposal(uint256 last) public {
        vm.prank(admin);
        voting.createProposal("test", last);
    }

    function vote(address _address, uint256 numberOfProposal, bool _value) public {
        uint256 balance = token.balanceOf(_address);

        vm.prank(_address);
        token.approve(address(voting), type(uint256).max);

        vm.prank(_address);
        voting.vote(numberOfProposal, balance, _value);
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
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_OwnerIsNotSigner() public {
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o2", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_DeadlineExpired() public {
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        vm.warp(101);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_MultiuseSameHash() public {
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);
    }

    function testFail_UseSygnatureToOtherProposal() public {
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        createProposal(VOTING_PERIOD);

        voting.permitVote(o1, 1, 10, true, 100, digest, v, r, s);
    }

    function test_DelegateByPermit() public {
        uint256 balanceBefore = token.balanceOf(o1);
        (uint8 v, bytes32 r, bytes32 s, bytes32 digest) = calculateRSV(o1, "o1", 0, 10, true, 100);

        voting.permitVote(o1, 0, 10, true, 100, digest, v, r, s);

        uint256 balanceAfter = token.balanceOf(o1);
        assertEq(balanceAfter + 10, balanceBefore);
    }

    function testFail_TokenApproveForDelegate() public {
        vm.prank(o1);
        token.approveForDelegate(o2, 1e18);
    }
}
