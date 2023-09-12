// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleVotingEvents {
    event NowProposal(uint256 indexed _numberOfProposal, uint256 _lastBlocks);
    event Voted(uint256 indexed _numberOfProposal, address indexed _voter, uint256 _votes, bool _yes);
    event NoResult(uint256 indexed _numberOfProposal);
    event Result(uint256 indexed _numberOfProposal, bool indexed _accepted);
}

contract SimpleVoting is SimpleVotingEvents {
    uint256 constant MIN_TOKENS_TO_CREATE_PROPOSAL = 10e18;
    uint256 constant MINIMUM = 2; // minimum voters that has to take part in the voting is the total amount of the token divided by this value 

    bool public locked = false;

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
        require(voteToken.balanceOf(msg.sender) > MIN_TOKENS_TO_CREATE_PROPOSAL, "Modifier: not enought tokens");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "NonReentract: locked");
        locked = true;
        _;
        locked = false;
    }

    function createProposal(bytes32 _name, uint256 lastBlocks)
        public
        enoughtTokens
        nonReentrant
        returns (uint256 numberOfProposal)
    {
        proposals.push(Proposal({name: _name, deadline: block.number + lastBlocks, yesCount: 0, noCount: 0}));
        numberOfProposal = proposals.length - 1;
        emit NowProposal(numberOfProposal, lastBlocks);
    }

    // You need approve tokens to this contract before you call vote
    function vote(uint256 numberOfProposal, uint256 votes, bool yes) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "Vote: too early");

        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedTokens[numberOfProposal][msg.sender] += votes;

        if (yes) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit Voted(numberOfProposal, msg.sender, votes, yes);
    }

    function withdraw(uint256 numberOfProposal) public nonReentrant {
        require(proposals[numberOfProposal].deadline < block.number, "Withdraw: too early");
        uint256 amount = lockedTokens[numberOfProposal][msg.sender];
        lockedTokens[numberOfProposal][msg.sender] = 0;
        if (amount < voteToken.balanceOf(address(this))) {
            voteToken.transfer(msg.sender, amount);
        } else {
            voteToken.transfer(msg.sender, voteToken.balanceOf(address(this)));
        }
    }

    function result(uint256 numberOfProposal) public nonReentrant {
        require(proposals[numberOfProposal].deadline < block.number, "Result: too early");
        uint256 yes = proposals[numberOfProposal].yesCount;
        uint256 no = proposals[numberOfProposal].noCount;
        if (yes + no <= voteToken.totalSupply() / MINIMUM) {
            emit NoResult(numberOfProposal);
        } else {
            bool outcome = yes > no ? true : false;
            emit Result(numberOfProposal, outcome);
        }
    }
}
