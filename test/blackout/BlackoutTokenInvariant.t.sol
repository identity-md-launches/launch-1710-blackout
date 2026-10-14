// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Independent ledger: only authorized successful transfers change model balances.
contract BlackoutTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public transfers;
    uint256 public delegatedTransfers;
    uint256 public rejectedCalls;

    constructor(LaunchToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 from, uint256 to, uint256 amount) public {
        address owner = actors[from % 4];
        address recipient = actors[to % 4];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        transfers++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) public {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        amount = infinite ? type(uint256).max : bound(amount, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 from, uint256 by, uint256 to, uint256 amount) public {
        address owner = actors[from % 4];
        address spender = actors[by % 4];
        address recipient = actors[to % 4];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        delegatedTransfers++;
    }

    function fullBalanceRoundTrip(uint256 who) external {
        uint256 from = who % 4;
        uint256 to = (from + 1) % 4;
        uint256 amount = expectedBalance[actors[from]];
        transfer(from, to, amount);
        transfer(to, from, amount);
    }

    function rejectOverspend(uint256 who, uint256 to) public {
        address owner = actors[who % 4];
        uint256 balance = expectedBalance[owner];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, balance + 1)
        );
        vm.prank(owner);
        token.transfer(actors[to % 4], balance + 1);
        rejectedCalls++;
    }

    function revokeAndRejectSpend(uint256 from, uint256 by) public {
        address owner = actors[from % 4];
        address spender = actors[by % 4];
        approve(from, by, 0, false);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
        rejectedCalls++;
    }

    function rejectZeroReceiver(uint256 from, uint256 amount) external {
        address owner = actors[from % 4];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
        rejectedCalls++;
    }

    function rejectMintAndBurn(uint256 who, uint256 amount) external {
        address actor = actors[who % 4];
        vm.prank(actor);
        (bool minted,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", actor, amount));
        assertFalse(minted, "no post-construction mint entry point");
        vm.prank(actor);
        (bool burned,) = address(token).call(abi.encodeWithSignature("burn(uint256)", amount));
        assertFalse(burned, "no burn entry point");
        rejectedCalls += 2;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract BlackoutTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken private token;
    BlackoutTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new LaunchToken();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("BLACKOUT token holder ", vm.toString(i)));
        }
        token.transfer(actors[0], SUPPLY);
        handler = new BlackoutTokenHandler(token, actors);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.spend.selector;
        selectors[3] = handler.fullBalanceRoundTrip.selector;
        selectors[4] = handler.rejectOverspend.selector;
        selectors[5] = handler.revokeAndRejectSpend.selector;
        selectors[6] = handler.rejectZeroReceiver.selector;
        selectors[7] = handler.rejectMintAndBurn.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetSender(makeAddr("BLACKOUT token executor"));
    }

    function invariant_FixedSupplyEqualsEveryHolderBalance() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_BalancesAndAllowancesMatchAuthorizedHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function test_HandlerCoversFullSupplyInfiniteAllowanceSelfTransferAndRevocation() public {
        handler.transfer(0, 0, SUPPLY);
        handler.fullBalanceRoundTrip(0);
        handler.approve(0, 1, 0, true);
        handler.spend(0, 1, 2, SUPPLY);
        assertEq(token.balanceOf(actors[2]), SUPPLY);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max);
        handler.revokeAndRejectSpend(0, 1);
        handler.approve(2, 3, SUPPLY, false);
        handler.spend(2, 3, 2, SUPPLY);
        assertEq(token.allowance(actors[2], actors[3]), 0);
        handler.rejectOverspend(2, 3);
        handler.rejectMintAndBurn(2, type(uint256).max);
        invariant_FixedSupplyEqualsEveryHolderBalance();
        invariant_BalancesAndAllowancesMatchAuthorizedHistory();
        assertGt(handler.transfers(), 0);
        assertGt(handler.delegatedTransfers(), 0);
        assertGt(handler.rejectedCalls(), 0);
    }
}
