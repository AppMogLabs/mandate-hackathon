// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RateToken} from "../src/RateToken.sol";

contract RateTokenTest is Test {
    RateToken public rateToken;
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        rateToken = new RateToken(admin);
    }

    // -------------------------------------------------------------------------
    // Deployment
    // -------------------------------------------------------------------------

    function test_Deployment_CorrectNameAndSymbol() public view {
        assertEq(rateToken.name(), "RATE");
        assertEq(rateToken.symbol(), "RATE");
    }

    function test_Deployment_InitialSupplyMintedToAdmin() public view {
        assertEq(rateToken.balanceOf(admin), rateToken.INITIAL_SUPPLY());
        assertEq(rateToken.totalSupply(), rateToken.INITIAL_SUPPLY());
    }

    function test_Deployment_AdminHasRoles() public view {
        assertTrue(rateToken.hasRole(rateToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(rateToken.hasRole(rateToken.MINTER_ROLE(), admin));
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert("RateToken: zero admin");
        new RateToken(address(0));
    }

    // -------------------------------------------------------------------------
    // Transfers
    // -------------------------------------------------------------------------

    function test_Transfer_Success() public {
        uint256 amount = 1000 * 1e18;
        vm.prank(admin);
        rateToken.transfer(alice, amount);
        assertEq(rateToken.balanceOf(alice), amount);
    }

    // -------------------------------------------------------------------------
    // Minting
    // -------------------------------------------------------------------------

    function test_Mint_ByMinter() public {
        uint256 amount = 500 * 1e18;
        vm.prank(admin);
        rateToken.mint(alice, amount);
        assertEq(rateToken.balanceOf(alice), amount);
    }

    function test_RevertWhen_MintByNonMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        rateToken.mint(alice, 100 * 1e18);
    }

    // -------------------------------------------------------------------------
    // Burning
    // -------------------------------------------------------------------------

    function test_Burn_Success() public {
        uint256 amount = 100 * 1e18;
        vm.prank(admin);
        rateToken.transfer(alice, amount);

        vm.prank(alice);
        rateToken.burn(50 * 1e18);
        assertEq(rateToken.balanceOf(alice), 50 * 1e18);
    }

    // -------------------------------------------------------------------------
    // Permit (EIP-2612)
    // -------------------------------------------------------------------------

    function test_Permit_DomainSeparator() public view {
        // Just verify it doesn't revert — domain separator is valid
        bytes32 ds = rateToken.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0));
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);

        uint256 balanceBefore = rateToken.balanceOf(to);
        vm.prank(admin);
        rateToken.mint(to, amount);
        assertEq(rateToken.balanceOf(to), balanceBefore + amount);
    }
}
