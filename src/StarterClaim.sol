// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FeeRouter} from "./FeeRouter.sol";
import {Params} from "./Params.sol";
import {FarmItems} from "./FarmItems.sol";
import {ICore} from "./interfaces/IGame.sol";
import {ChainClock} from "./lib/ChainClock.sol";
import {ItemMath} from "./lib/ItemMath.sol";
import "./lib/Errors.sol";

contract StarterClaim is GameModule, ReentrancyGuard {
    struct Claim {
        address player;
        uint64 target;
        bool resolved;
    }

    function freeRoot() public view returns (bytes32) {
        return registry.freeRoot();
    }
    uint256 public freeClaimed;
    mapping(address => bool) public freeClaimedBy;
    mapping(uint256 => bool) public freeIndexClaimed;
    event FreePackClaimed(address indexed player, uint256 indexed index, uint256 receipt);

    function freeClaimEnds() public view returns (uint256) {
        return launchTime() + 30 days;
    }

    function claimFree(uint256 index, bytes32[] calldata proof) external nonReentrant returns (uint256 id) {
        if (freeRoot() == bytes32(0)) revert NotConfigured();
        if (block.timestamp >= freeClaimEnds()) revert TooEarly();
        if (index >= 500 || freeClaimed >= 500 || freeIndexClaimed[index] || freeClaimedBy[msg.sender]) {
            revert InvalidValue();
        }
        if (!MerkleProof.verifyCalldata(proof, freeRoot(), keccak256(abi.encode(index, msg.sender)))) {
            revert InvalidProof();
        }
        freeIndexClaimed[index] = true;
        freeClaimedBy[msg.sender] = true;
        ++freeClaimed;
        id = (uint256(1) << 255) | index;
        claims[id] = Claim(msg.sender, uint64(ChainClock.number() + 2), false);
        farm().register(msg.sender);
        emit StarterCommitted(id, msg.sender, ChainClock.number() + 2);
        emit FreePackClaimed(msg.sender, index, id);
    }
    mapping(uint256 => bool) public entropyCaptured;
    mapping(uint256 => bytes32) public entropyHash;
    mapping(uint256 => Claim) public claims;
    event StarterCommitted(uint256 indexed tokenId, address indexed holder, uint256 target);
    event StarterResolved(uint256 indexed tokenId, bool expired);

    constructor(address registry_) GameModule(registry_) {}

    function root() public view returns (bytes32) {
        return registry.starterRoot();
    }

    function snapshotBlock() public view returns (uint256) {
        return registry.snapshotBlock();
    }

    function launchTime() public view returns (uint256) {
        return registry.launchTime();
    }

    function items() public view returns (FarmItems) {
        return FarmItems(registry.module(3));
    }

    function farm() public view returns (ICore) {
        return ICore(registry.module(2));
    }

    function fees() public view returns (FeeRouter) {
        return FeeRouter(payable(registry.module(6)));
    }

    function claim(uint256 tokenId, bytes32[] calldata proof) external nonReentrant {
        if (block.timestamp < launchTime() + 48 hours || block.timestamp >= launchTime() + 16 days) revert TooEarly();
        if (tokenId >= uint256(1) << 255) revert InvalidValue();
        if (claims[tokenId].player != address(0)) revert AlreadyDone();
        if (!MerkleProof.verifyCalldata(proof, root(), keccak256(abi.encode(tokenId, msg.sender)))) {
            revert InvalidProof();
        }
        uint64 target = uint64(ChainClock.number() + 2);
        claims[tokenId] = Claim(msg.sender, target, false);
        farm().register(msg.sender);
        emit StarterCommitted(tokenId, msg.sender, target);
    }

    function captureEntropy(uint256 tokenId) external nonReentrant {
        _capture(tokenId, msg.sender);
    }

    function _capture(uint256 tokenId, address keeper) private returns (bool) {
        uint256 startGas = gasleft();
        Claim storage c = claims[tokenId];
        if (c.player == address(0)) revert InvalidValue();
        if (entropyCaptured[tokenId]) return true;
        if (ChainClock.number() <= c.target) revert TooEarly();
        bytes32 h = ChainClock.hash(c.target);
        if (h == bytes32(0)) {
            if (ChainClock.number() <= uint256(c.target) + 256) revert NotConfigured();
            _rearm(tokenId, c);
            return false;
        }
        entropyHash[tokenId] = h;
        entropyCaptured[tokenId] = true;
        fees().payWork(keeper, Params.Key.EntropyBounty, 1, startGas - gasleft());
        return true;
    }

    event StarterRearmed(uint256 indexed tokenId, uint256 target);

    function rearm(uint256 tokenId) external {
        Claim storage c = claims[tokenId];
        if (c.player == address(0)) revert InvalidValue();
        if (c.resolved || entropyCaptured[tokenId] || ChainClock.number() <= uint256(c.target) + 256) {
            revert TooEarly();
        }
        _rearm(tokenId, c);
    }

    function _rearm(uint256 tokenId, Claim storage c) private {
        c.target = uint64(ChainClock.number() + 2);
        emit StarterRearmed(tokenId, c.target);
    }

    function resolve(uint256 tokenId) external nonReentrant {
        Claim storage c = claims[tokenId];
        if (c.player == address(0)) revert InvalidValue();
        if (c.resolved) revert AlreadyDone();
        if (ChainClock.number() <= c.target) revert TooEarly();
        if (!_capture(tokenId, msg.sender)) return;
        if (items().inventory(c.player) + 3 > items().capacity(c.player)) revert InsufficientBalance();
        c.resolved = true;
        bytes32 h = entropyHash[tokenId];
        for (uint256 i; i < 3; ++i) {
            (uint8 k, uint8 r) = ItemMath.draw(keccak256(abi.encode(h, address(this), tokenId, i)), false, true);
            items().mint(c.player, k, r, true);
        }
        emit StarterResolved(tokenId, h == bytes32(0));
    }
}
