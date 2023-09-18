// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VotingWithSnapshot} from "./VotingWithSnapshot.sol";
import {SnapshotToken} from "./utility/SnapshotToken.sol";

contract NonlinearVoting is VotingWithSnapshot {
    constructor(address voteTokenAddress, string memory name) VotingWithSnapshot(voteTokenAddress, name) {}

    function delegateVote(uint256 numberOfProposal, uint256 votes, bool choose) public override nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "DelegateVote: too late");

        require(!useDelegateVote[numberOfProposal][msg.sender][choose]);
        useDelegateVote[numberOfProposal][msg.sender][choose] = true;

        require(votes <= delegatedTokens[numberOfProposal][msg.sender], "DelegatedVote: too many votes");
        delegatedTokens[numberOfProposal][msg.sender] -= votes;

        uint256 newVotes = _calculateVotes(votes);

        if (choose) {
            proposals[numberOfProposal].yesCount += newVotes;
        } else {
            proposals[numberOfProposal].noCount += newVotes;
        }
        emit DelegateVoted(numberOfProposal, msg.sender, newVotes, choose);
    }

    function _vote(address voter, uint256 numberOfProposal, uint256 votes, bool choose) internal override {
        require(proposals[numberOfProposal].deadline > block.number, "Vote: too late");

        require(!tookParticipate[numberOfProposal][voter]);
        tookParticipate[numberOfProposal][voter] = true;
        uint256 snapshotID = proposals[numberOfProposal].snapshotID;

        require(voteToken.balanceOfAt(voter, snapshotID) >= votes, "Vote: not enought tokens");

        lockedTokens[numberOfProposal][voter] += votes;

        uint256 newVotes = _calculateVotes(votes);

        if (choose) {
            proposals[numberOfProposal].yesCount += newVotes;
        } else {
            proposals[numberOfProposal].noCount += newVotes;
        }
        emit Voted(numberOfProposal, voter, newVotes, choose);
    }

    // calculate sqrt(_votes)
    function _calculateVotes(uint256 _votes) public pure returns (uint256 newVotes) {
        if (_votes > 3) {
            newVotes = _votes;
            uint256 x = _votes / 2 + 1;
            while (x < newVotes) {
                newVotes = x;
                x = (_votes / x + x) / 2;
            }
        } else if (_votes != 0) {
            newVotes = 1;
        }
    }
}
