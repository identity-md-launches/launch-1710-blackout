// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Test-only factory: verifies that construction mints to the factory, never tx.origin.
contract LaunchTokenFactoryFixture {
    function deploy() external returns (LaunchToken) {
        return new LaunchToken();
    }
}

contract LaunchTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    LaunchToken private token;
    address private recipient;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
        recipient = makeAddr("token recipient");
        spender = makeAddr("approved spender");
    }

    function testMetadataAndFixedSupply() public view {
        assertEq(token.name(), "BLACKOUT");
        assertEq(token.symbol(), "BLACKOUT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFactoryReceivesEntireSupplyInsteadOfOriginOrCaller() public {
        LaunchTokenFactoryFixture factory = new LaunchTokenFactoryFixture();
        address payer = makeAddr("launch payer");
        vm.prank(payer, payer);
        LaunchToken launched = factory.deploy();
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(payer), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testLaunchAllocationsAndSubsequentEndowmentTransferArePlainTransfers() public {
        // Local allocation actors are fixtures, not proposed production addresses.
        address pool = makeAddr("pool allocation");
        address distributor = makeAddr("swarm distributor");
        address payer = makeAddr("paying wallet");
        address escrow = 0x11947494C0BA91508eB7409648193818C36521Fb;
        assertTrue(token.transfer(pool, 700_000_000e18));
        assertTrue(token.transfer(distributor, 100_000_000e18));
        assertTrue(token.transfer(payer, 200_000_000e18));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(escrow), 0, "no constructor allocation to escrow");
        vm.prank(payer);
        assertTrue(token.transfer(escrow, 200_000_000e18));
        assertEq(token.balanceOf(escrow), 200_000_000e18);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(pool) + token.balanceOf(distributor) + token.balanceOf(escrow), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransfersConserveSupplyWithoutFees(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, amount);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testZeroAndSelfTransfers() public {
        assertTrue(token.transfer(recipient, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromSpendsOnlyApprovedAmount(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteAllowanceRetainedAndCanBeRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1 ether);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(recipient), 1 ether);
    }

    function testCannotSpendAnotherHoldersBalanceWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testTransferAboveBalanceRevertsWithoutChangingSupply() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(recipient);
        token.transfer(spender, 1);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromFailureRestoresAllowance() public {
        vm.prank(recipient);
        token.approve(spender, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(recipient, address(this), 1 ether);
        assertEq(token.allowance(recipient, spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testZeroRecipientAndSpenderRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintBurnOwnerPauseBlacklistOrUpgradeEntryPoints() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "pause()",
            "blacklist(address)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], recipient, 1 ether);
            (bool deployerOk,) = address(token).call(data);
            assertFalse(deployerOk, signatures[i]);
            vm.prank(recipient);
            (bool outsiderOk,) = address(token).call(data);
            assertFalse(outsiderOk, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testRuntimeHasNoUpgradeOrDestructionOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf2 && op != 0xf4 && op != 0xff);
            }
        }
    }
}
