// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "./utility/Nonces.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VotingWithDelegate, VotingWithDelegateEvents} from "./VotingWithDelegate.sol";

interface IERC20WithPermit is IERC20 {
    function approveForDelegate(address, uint256) external;
}

contract VotingWithPermitEvents is VotingWithDelegateEvents {
    event DelegatedByPermit(
        address indexed _from, address indexed _to, uint256 indexed numberOfProposal, uint256 votes
    );
}

contract VotingWithPermit is VotingWithPermitEvents, EIP712, Nonces {
    error ERC2612ExpiredSignature(uint256 deadline);

    error ERC2612InvalidSigner(address signer, address owner);

    using ECDSA for bytes32;

    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 numberOfProposal, uint256 value,uint256 nonce,uint256 deadline)"
    );

    uint256 constant MINIMUM = 2; // minimum voters that has to take part in the voting is the total amount of the token divided by this

    address public proposer; // address which is able to create a new Proposal

    bool public locked = false;

    struct Proposal {
        bytes32 name; // short name (up to 32 bytes)
        uint256 deadline; // expiring of the proposal
        uint256 yesCount; // number of possitive votes
        uint256 noCount; // number of negative votes
    }

    Proposal[] public proposals;

    IERC20WithPermit public voteToken;

    mapping(uint256 => mapping(address => uint256)) lockedTokens;
    mapping(uint256 => mapping(address => uint256)) lockedDelegatedTokens;
    mapping(uint256 => mapping(address => uint256)) delegatedTokens;

    constructor(address voteTokenAddress, string memory name) EIP712(name, "1") {
        voteToken = IERC20WithPermit(voteTokenAddress);
        proposer = msg.sender;
    }

    modifier Proposer() {
        require(msg.sender == proposer, "Modifier: you're not proposer");
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

    function createProposal(bytes32 _name, uint256 lastBlocks)
        public
        Proposer
        nonReentrant
        returns (uint256 numberOfProposal)
    {
        proposals.push(Proposal({name: _name, deadline: block.number + lastBlocks, yesCount: 0, noCount: 0}));
        numberOfProposal = proposals.length - 1;
        emit NowProposal(numberOfProposal, lastBlocks);
    }

    // send tokens to this contract and give access to address 'to' to vote by this tokens, before you have to approved tokens to the contract
    function delegate(address to, uint256 numberOfProposal, uint256 votes) public nonReentrant {
        require(voteToken.balanceOf(msg.sender) >= votes, "Delegate: not enought tokens");
        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedDelegatedTokens[numberOfProposal][msg.sender] += votes;
        delegatedTokens[numberOfProposal][to] += votes;
        emit Delegated(msg.sender, to, numberOfProposal, votes);
    }

    /* you could give signed massage to someone to use this function. This function transfer tokens from your 
    address to the address of contract and give access to spender to use it in the voting. You don't need approved tokens before
    */
    function permit(
        address _owner,
        address spender,
        uint256 numberOfProposal,
        uint256 value,
        uint256 deadline,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }
        bytes32 digest;
        {
            uint256 _nonce = nonces(_owner) + 1;
            digest = keccak256(
                abi.encode(PERMIT_TYPEHASH, _owner, spender, numberOfProposal, value, _nonce, deadline)
            ).toEthSignedMessageHash();
        }

        require(hash == digest, "Permit: wrong hash");

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != _owner) {
            revert ERC2612InvalidSigner(signer, _owner);
        }
        
        _useNonce(_owner);

        voteToken.approveForDelegate(_owner, value);

        _delegateByPermit(_owner, spender, numberOfProposal, value);
    }

    function vote(uint256 numberOfProposal, uint256 votes, bool yes) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "Vote: too late");

        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedTokens[numberOfProposal][msg.sender] += votes;

        if (yes) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit Voted(numberOfProposal, msg.sender, votes, yes);
    }

    function delegateVote(uint256 numberOfProposal, uint256 votes, bool yes) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "DelegateVote: too late");

        require(votes <= delegatedTokens[numberOfProposal][msg.sender], "DelegatedVote: too many votes");
        delegatedTokens[numberOfProposal][msg.sender] -= votes;

        if (yes) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit DelegateVoted(numberOfProposal, msg.sender, votes, yes);
    }

    function withdraw(uint256 numberOfProposal) public nonReentrant {
        require(proposals[numberOfProposal].deadline < block.number, "Withdraw: too early");
        uint256 lockedAmount = lockedTokens[numberOfProposal][msg.sender];
        lockedTokens[numberOfProposal][msg.sender] = 0;

        uint256 delegatedAmount = lockedDelegatedTokens[numberOfProposal][msg.sender];
        lockedDelegatedTokens[numberOfProposal][msg.sender] = 0;

        if (lockedAmount + delegatedAmount < voteToken.balanceOf(address(this))) {
            voteToken.transfer(msg.sender, lockedAmount + delegatedAmount);
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

    function _delegateByPermit(address from, address to, uint256 numberOfProposal, uint256 votes)
        internal
        nonReentrant
    {
        require(voteToken.balanceOf(from) >= votes, "Delegate: not enought tokens");
        voteToken.transferFrom(from, address(this), votes);
        lockedDelegatedTokens[numberOfProposal][from] += votes;
        delegatedTokens[numberOfProposal][to] += votes;
        emit DelegatedByPermit(from, to, numberOfProposal, votes);
    }
}
