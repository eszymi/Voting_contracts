// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// utilities
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
// core contracts
import {Token} from "contracts/utility/Token.sol";
import {SimpleVoting, SimpleVotingEvents} from "contracts/SimpleVoting.sol";

contract SimpleVotingTest is Test, SimpleVotingEvents {
    uint256 public constant VOTING_PERIOD = 3600;

    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address o3 = makeAddr("o3");
    address o4 = makeAddr("o4");
    address admin = makeAddr("admin");

    Token token;
    SimpleVoting voting;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(o1, 10_000 ether);
        vm.deal(o2, 10_000 ether);
        vm.deal(o3, 10_000 ether);
        vm.deal(o4, 10_000 ether);

        // deploying token + core contract
        vm.prank(admin);
        token = new Token('VotingToken','VT');

        vm.prank(admin);
        voting = new SimpleVoting(address(token));

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
        vm.prank(o3);
        voting.createProposal("test", last);
    }

    function vote(address _address, uint256 numberOfProposal, bool _value) public {
        uint256 balance = token.balanceOf(_address);

        vm.prank(_address);
        token.approve(address(voting), type(uint256).max);

        vm.prank(_address);
        voting.vote(numberOfProposal, balance, _value);
    }

    function testFail_TooLessTokens() public {
        vm.prank(o4);
        voting.createProposal("test", VOTING_PERIOD);
    }

    function test_EnoughtTokens() public {
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

        vm.expectEmit(true , false, false, true);
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
