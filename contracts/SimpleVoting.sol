// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleVotingEvents {
    event NowProposal(uint256 indexed _numberOfProposal, uint256 _lastTime);
    event Voted(uint256 indexed _numberOfProposal, address indexed _voter, uint256 _votes, bool _yes);
    event NoResult(uint256 indexed _numberOfProposal);
    event Result(uint256 indexed _numberOfProposal, bool indexed _accepted);
}

contract SimpleVoting is SimpleVotingEvents {
    uint256 constant minTokensToCreateProposal = 10e18;
    uint256 constant minimum = 2; // minimum voters that has to take part in the voting is the total amount of the token divided by this value

    struct Proposal {
        bytes32 name; // short name (up to 32 bytes)
        uint256 deadline; // expiring of the proposal
        uint256 yesCount; // number of possitive votes
        uint256 noCount; // number of negative votes
    }

    Proposal[] public proposals;

    IERC20 public voteToken;

    mapping(uint256 => mapping(address => uint256)) lockedTokens;

    constructor(address voteTokenAddress) {
        voteToken = IERC20(voteTokenAddress);
    }

    modifier enoughtTokens() {
        require(voteToken.balanceOf(msg.sender) > minTokensToCreateProposal);
        _;
    }

    function createProposal(bytes32 _name, uint256 lastTime) public enoughtTokens returns (uint256 numberOfProposal) {
        proposals.push(Proposal({name: _name, deadline: block.timestamp + lastTime, yesCount: 0, noCount: 0}));
        numberOfProposal = proposals.length - 1;
        emit NowProposal(numberOfProposal, lastTime);
    }

    function vote(uint256 numberOfProposal, uint256 votes, bool yes) public {
        require(proposals[numberOfProposal].deadline > block.timestamp);

        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedTokens[numberOfProposal][msg.sender] += votes;

        if (yes) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit Voted(numberOfProposal, msg.sender, votes, yes);
    }

    function withdraw(uint256 numberOfProposal) public {
        require(proposals[numberOfProposal].deadline < block.timestamp);
        uint256 amount = lockedTokens[numberOfProposal][msg.sender];
        lockedTokens[numberOfProposal][msg.sender] = 0;
        if (amount < voteToken.balanceOf(address(this))) {
            voteToken.transfer(msg.sender, amount);
        } else {
            voteToken.transfer(msg.sender, voteToken.balanceOf(address(this)));
        }
    }

    function result(uint256 numberOfProposal) public {
        require(proposals[numberOfProposal].deadline < block.timestamp);
        uint256 yes = proposals[numberOfProposal].yesCount;
        uint256 no = proposals[numberOfProposal].noCount;
        if (yes + no <= voteToken.totalSupply() / minimum) {
            emit NoResult(numberOfProposal);
        } else {
            bool outcome = yes > no ? true : false;
            emit Result(numberOfProposal, outcome);
        }
    }
}
