// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "./utility/Nonces.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VotingWithPermit, VotingWithPermitEvents} from "./VotingWithPermit.sol";
import {SnapshotToken} from "./utility/SnapshotToken.sol";

contract VotingWithSnapshotEvents {
    event NewProposer(address indexed _oldProposer, address indexed _newProposer);
    event NewSnapshoter(address indexed oldSnapshoter, address indexed newSnapshoter);
    event NowProposal(uint256 indexed _numberOfProposal, uint256 _lastBlocks, uint256 _snapshotID);
    event Delegated(
        address indexed _from,
        address indexed _to,
        uint256 indexed _numberOfProposal,
        uint256 _snapshotID,
        uint256 _votes
    );
    event Voted(uint256 indexed _numberOfProposal, address indexed _voter, uint256 _votes, bool _yes);
    event PermitVoted(uint256 indexed _numberOfProposal, address indexed _voter, uint256 _votes, bool _choose);
    event DelegateVoted(
        uint256 indexed _numberOfProposal, address indexed _delegatedVoter, uint256 _votes, bool _choose
    );
    event NoResult(uint256 indexed _numberOfProposal);
    event Result(uint256 indexed _numberOfProposal, bool indexed _accepted);
}

contract VotingWithSnapshot is VotingWithSnapshotEvents, EIP712, Nonces {
    error ERC2612ExpiredSignature(uint256 deadline);

    error ERC2612InvalidSigner(address signer, address owner);

    using ECDSA for bytes32;

    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner, uint256 numberOfProposal, uint256 votes, bool choose, uint256 nonce, uint256 deadline)"
    );

    uint256 constant MINIMUM = 2; // minimum voters that has to take part in the voting is the total amount of the token divided by this

    address public proposer; // address which is able to create a new Proposal
    address public snapshoter; // address which is able make a new snapshot

    bool public locked = false;

    struct Proposal {
        bytes32 name; // short name (up to 32 bytes)
        uint256 snapshotID; //id of the snapshot used in this proposal
        uint256 deadline; // expiring of the proposal
        uint256 yesCount; // number of possitive votes
        uint256 noCount; // number of negative votes
    }

    Proposal[] public proposals;

    SnapshotToken public voteToken;

    mapping(uint256 => mapping(address => uint256)) public lockedTokens;
    mapping(uint256 => mapping(address => uint256)) public lockedDelegatedTokens;
    mapping(uint256 => mapping(address => uint256)) public delegatedTokens;
    mapping(uint256 => mapping(address => bool)) public tookParticipate;
    mapping(uint256 => mapping(address => mapping(bool => bool))) public useDelegateVote; //one persone can voty by delegate twice, one for each option

    constructor(address voteTokenAddress, string memory name) EIP712(name, "1") {
        voteToken = SnapshotToken(voteTokenAddress);
        proposer = msg.sender;
        snapshoter = msg.sender;
    }

    modifier Proposer() {
        require(msg.sender == proposer, "Modifier: you're not proposer");
        _;
    }

    modifier Snapshoter() {
        require(msg.sender == snapshoter, "Modifier: you're not snapshoter");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "NonReentract: locked");
        locked = true;
        _;
        locked = false;
    }

    function changeProposer(address _newProposer) public Proposer {
        proposer = _newProposer;
        emit NewProposer(msg.sender, _newProposer);
    }

    function changeSnapshoter(address _newSnapshoter) external Snapshoter {
        snapshoter = _newSnapshoter;
        emit NewSnapshoter(msg.sender, _newSnapshoter);
    }

    function makeSnapshot() external Snapshoter {
        voteToken.snapshot();
    }

    function createProposal(bytes32 _name, uint256 lastBlocks, uint256 snapshotID)
        public
        Proposer
        nonReentrant
        returns (uint256 numberOfProposal)
    {
        proposals.push(
            Proposal({name: _name, snapshotID: snapshotID, deadline: block.number + lastBlocks, yesCount: 0, noCount: 0})
        );
        numberOfProposal = proposals.length - 1;
        emit NowProposal(numberOfProposal, lastBlocks, snapshotID);
    }

    // send tokens to this contract and give access to address 'to' to vote by this tokens
    function delegate(address to, uint256 numberOfProposal, uint256 snapshotID, uint256 votes) public nonReentrant {
        require(!tookParticipate[numberOfProposal][msg.sender]);
        tookParticipate[numberOfProposal][msg.sender] = true;

        require(voteToken.balanceOfAt(msg.sender, snapshotID) >= votes, "Delegate: not enought tokens");
        lockedDelegatedTokens[numberOfProposal][msg.sender] += votes;
        delegatedTokens[numberOfProposal][to] += votes;
        emit Delegated(msg.sender, to, numberOfProposal, snapshotID, votes);
    }

    /* you could give signed massage to someone to use this function. This function transfer tokens from your 
    address to the address of contract and then it call _vote function. 
    Thanks that you don't need to pay for the gas. You don't need approved tokens before
    */
    function permitVote(
        address _owner,
        uint256 numberOfProposal,
        uint256 votes,
        bool choose,
        uint256 deadline,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public nonReentrant {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }
        bytes32 digest;
        {
            uint256 _nonce = nonces(_owner) + 1;
            digest = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, numberOfProposal, votes, choose, _nonce, deadline))
                .toEthSignedMessageHash();
        }

        require(hash == digest, "Permit: wrong hash");

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != _owner) {
            revert ERC2612InvalidSigner(signer, _owner);
        }

        _useNonce(_owner);

        _vote(_owner, numberOfProposal, votes, choose);

        emit PermitVoted(numberOfProposal, _owner, votes, choose);
    }

    function vote(uint256 numberOfProposal, uint256 votes, bool choose) public nonReentrant {
        _vote(msg.sender, numberOfProposal, votes, choose);
    }

    function delegateVote(uint256 numberOfProposal, uint256 votes, bool choose) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "DelegateVote: too late");

        require(!useDelegateVote[numberOfProposal][msg.sender][choose]);
        useDelegateVote[numberOfProposal][msg.sender][choose] = true;

        require(votes <= delegatedTokens[numberOfProposal][msg.sender], "DelegatedVote: too many votes");
        delegatedTokens[numberOfProposal][msg.sender] -= votes;

        if (choose) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit DelegateVoted(numberOfProposal, msg.sender, votes, choose);
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

    function _vote(address voter, uint256 numberOfProposal, uint256 votes, bool choose) internal {
        require(proposals[numberOfProposal].deadline > block.number, "Vote: too late");

        require(!tookParticipate[numberOfProposal][voter]);
        tookParticipate[numberOfProposal][voter] = true;
        uint256 snapshotID = proposals[numberOfProposal].snapshotID;

        require(voteToken.balanceOfAt(voter, snapshotID) >= votes, "Vote: not enought tokens");

        lockedTokens[numberOfProposal][voter] += votes;

        if (choose) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit Voted(numberOfProposal, voter, votes, choose);
    }
}
