// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ItemMetadata} from "./lib/ItemMetadata.sol";
import {ItemMath} from "./lib/ItemMath.sol";
import {EconomyMath} from "./lib/EconomyMath.sol";
import {GameModule} from "./lib/GameModule.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/Errors.sol";

/// @notice Each ERC1155 id is one soulbound item; durability and overclock survive custody changes.
contract FarmItems is GameModule, ERC1155, ReentrancyGuard {
    struct Item {
        address holder;
        uint16 durability;
        uint8 kind;
        uint8 rarity;
        uint8 overclock;
        bool starter;
        bool equipped;
    }

    uint256 public nextId = 1;
    mapping(address => uint256[]) private owned;
    mapping(uint256 => uint256) private ownerIndex;

    function itemsByOwner(address p, uint256 offset, uint256 limit) external view returns (uint256[] memory ids) {
        if (limit > 100) revert InvalidValue();
        uint256 end = offset + limit;
        if (end > owned[p].length) end = owned[p].length;
        if (offset > end) offset = end;
        ids = new uint256[](end - offset);
        for (uint256 i; i < ids.length; ++i) {
            ids[i] = owned[p][offset + i];
        }
    }

    function ownedCount(address p) external view returns (uint256) {
        return owned[p].length;
    }

    function outputTier(uint256 id) external view returns (uint256) {
        if (item[id].holder == address(0)) revert InvalidValue();
        return EconomyMath.tier(item[id].durability);
    }

    function uri(uint256 id) public view override returns (string memory) {
        Item memory x = item[id];
        if (x.holder == address(0)) revert InvalidValue();
        return ItemMetadata.render(id, x.kind, x.rarity, x.overclock, x.durability, x.starter);
    }
    mapping(uint256 => Item) public item;
    mapping(address => uint256) public inventory;
    mapping(address => uint256) public expansions;
    event ItemChanged(uint256 indexed id, uint256 durability, uint256 overclock);

    constructor(address registry_) GameModule(registry_) ERC1155("BLACKOUT-v3:soulbound") {}

    function engine() public view returns (address) {
        return registry.module(9);
    }

    function packSale() public view returns (address) {
        return registry.module(4);
    }

    function starterClaim() public view returns (address) {
        return registry.module(5);
    }

    function farmCore() public view returns (address) {
        return registry.module(2);
    }

    function season() public view returns (address) {
        return registry.module(8);
    }
    modifier onlyCore() {
        if (msg.sender != farmCore()) revert Unauthorized();
        _;
    }

    function capacity(address p) public view returns (uint256) {
        return 15 + 5 * expansions[p];
    }

    function data(uint256 id) external view returns (Item memory) {
        return item[id];
    }

    function mint(address p, uint8 k, uint8 r, bool starter) public nonReentrant returns (uint256 id) {
        bool allowed = msg.sender == starterClaim() || msg.sender == packSale() || msg.sender == farmCore()
            || msg.sender == season() || msg.sender == registry.module(12);
        if (!allowed || (starter && msg.sender == registry.module(12))) revert Unauthorized();
        if (p == address(0) || k >= 12 || r >= 5 || inventory[p] >= capacity(p)) revert InvalidValue();
        id = nextId++;
        item[id] = Item(p, 10000, k, r, 0, starter, false);
        ownerIndex[id] = owned[p].length;
        owned[p].push(id);
        inventory[p]++;
        _mint(p, id, 1, "");
    }

    function mintDrop(address p, bytes32 seed) external onlyCore returns (uint256) {
        (uint8 k, uint8 r) = ItemMath.draw(seed, false, false);
        return mint(p, k, r == 0 ? 0 : 1, false);
    }

    function equip(address p, uint256 id) external onlyCore {
        Item storage x = item[id];
        if (x.holder != p || x.equipped) revert Unauthorized();
        x.equipped = true;
        inventory[p]--;
        _safeTransferFrom(p, farmCore(), id, 1, "");
    }

    function unequip(address p, uint256 id) external onlyCore {
        Item storage x = item[id];
        if (x.holder != p || !x.equipped || inventory[p] >= capacity(p)) revert InvalidValue();
        x.equipped = false;
        inventory[p]++;
        _safeTransferFrom(farmCore(), p, id, 1, "");
    }

    function destroy(uint256 id) external {
        if (msg.sender != farmCore() && msg.sender != engine() && msg.sender != registry.module(11)) {
            revert Unauthorized();
        }
        Item memory x = item[id];
        if (x.holder == address(0)) revert InvalidValue();
        uint256 index = ownerIndex[id];
        uint256 last = owned[x.holder][owned[x.holder].length - 1];
        owned[x.holder][index] = last;
        ownerIndex[last] = index;
        owned[x.holder].pop();
        delete ownerIndex[id];
        delete item[id];
        if (!x.equipped) inventory[x.holder]--;
        _burn(x.equipped ? farmCore() : x.holder, id, 1);
    }

    function maintain(uint256 id, uint16 durability, uint8 overclock) external {
        if (
            msg.sender != farmCore() && msg.sender != engine() && msg.sender != registry.module(10)
                && msg.sender != registry.module(11)
        ) revert Unauthorized();
        if (item[id].holder == address(0) || durability > 10000 || overclock > 16) revert InvalidValue();
        item[id].durability = durability;
        item[id].overclock = overclock;
        emit ItemChanged(id, durability, overclock);
    }

    function expand(address p) external onlyCore {
        expansions[p]++;
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Unauthorized();
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts) internal override {
        if (from != address(0) && to != address(0) && msg.sender != farmCore()) revert Unauthorized();
        super._update(from, to, ids, amounts);
    }
}
