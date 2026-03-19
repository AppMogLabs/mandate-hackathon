// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ResourceTokenFactory} from "../src/ResourceTokenFactory.sol";
import {ResourceToken} from "../src/ResourceToken.sol";

contract ResourceTokenFactoryTest is Test {
    ResourceTokenFactory public factory;
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");

    function setUp() public {
        factory = new ResourceTokenFactory(admin);
    }

    // -------------------------------------------------------------------------
    // Deployment
    // -------------------------------------------------------------------------

    function test_Deployment_AdminHasRoles() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.DEPLOYER_ROLE(), admin));
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert("ResourceTokenFactory: zero admin");
        new ResourceTokenFactory(address(0));
    }

    // -------------------------------------------------------------------------
    // Deploy resource
    // -------------------------------------------------------------------------

    function test_DeployResource_COMPUTE() public {
        vm.prank(admin);
        address token = factory.deployResource("COMPUTE", "COMPUTE");

        assertTrue(token != address(0));
        assertEq(factory.getTokenAddress("COMPUTE"), token);
        assertEq(factory.deployedTokenCount(), 1);

        ResourceToken rt = ResourceToken(token);
        assertEq(rt.name(), "COMPUTE");
        assertEq(rt.symbol(), "COMPUTE");
    }

    function test_DeployResource_MultipleDeploys() public {
        vm.startPrank(admin);
        address compute = factory.deployResource("COMPUTE", "COMPUTE");
        address chips = factory.deployResource("CHIPS", "CHIPS");
        vm.stopPrank();

        assertTrue(compute != chips);
        assertEq(factory.deployedTokenCount(), 2);
        assertEq(factory.getTokenAddress("COMPUTE"), compute);
        assertEq(factory.getTokenAddress("CHIPS"), chips);
    }

    function test_RevertWhen_DeployDuplicate() public {
        vm.startPrank(admin);
        factory.deployResource("COMPUTE", "COMPUTE");

        vm.expectRevert("ResourceTokenFactory: already deployed");
        factory.deployResource("COMPUTE v2", "COMPUTE");
        vm.stopPrank();
    }

    function test_RevertWhen_DeployByNonDeployer() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployResource("COMPUTE", "COMPUTE");
    }

    // -------------------------------------------------------------------------
    // Mint authority
    // -------------------------------------------------------------------------

    function test_SetMintAuthority_GrantAndMint() public {
        vm.startPrank(admin);
        address token = factory.deployResource("COMPUTE", "COMPUTE");
        factory.setMintAuthority(token, alice, true);
        vm.stopPrank();

        ResourceToken rt = ResourceToken(token);

        vm.prank(alice);
        rt.mint(alice, 1000 * 1e18);
        assertEq(rt.balanceOf(alice), 1000 * 1e18);
    }

    function test_SetMintAuthority_RevokeAndFail() public {
        vm.startPrank(admin);
        address token = factory.deployResource("COMPUTE", "COMPUTE");
        factory.setMintAuthority(token, alice, true);
        factory.setMintAuthority(token, alice, false);
        vm.stopPrank();

        ResourceToken rt = ResourceToken(token);

        vm.prank(alice);
        vm.expectRevert();
        rt.mint(alice, 1000 * 1e18);
    }

    // -------------------------------------------------------------------------
    // Factory-minted tokens have correct admin
    // -------------------------------------------------------------------------

    function test_FactoryIsAdminOfDeployedToken() public {
        vm.prank(admin);
        address token = factory.deployResource("COMPUTE", "COMPUTE");

        ResourceToken rt = ResourceToken(token);
        assertTrue(rt.hasRole(rt.DEFAULT_ADMIN_ROLE(), address(factory)));
    }

    // -------------------------------------------------------------------------
    // Lookup non-existent symbol
    // -------------------------------------------------------------------------

    function test_GetTokenAddress_ReturnsZeroForUnknown() public view {
        assertEq(factory.getTokenAddress("NONEXISTENT"), address(0));
    }
}
