const whitelistedAddresses = require("./whitelistedAddresses.json");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

function isEqualToClaimAddress(value) {
  return value == claimingAddress;
}

const index = 2;

const leaves = whitelistedAddresses.map((v) => keccak256(v));
const tree = new MerkleTree(leaves, keccak256, { sort: true });
const root = tree.getHexRoot();
const leaf = keccak256(whitelistedAddresses[index]);
const proof = tree.getHexProof(leaf);
console.log("root:", root);
console.log("leaf before hash", whitelistedAddresses[index]);
console.log("proof", proof);

