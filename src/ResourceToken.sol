// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ResourceToken — ERC-20 template for individual resource types
/// @notice Deployed by ResourceTokenFactory via Clones (EIP-1167). Each instance
///         represents one resource: COMPUTE, CHIPS, ENERGY, etc.
/// @dev Minting restricted to MINTER_ROLE (granted to factory, then to authorized buildings).
///      Uses initialize() instead of constructor for clone compatibility.
contract ResourceToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Deploy the resource token template.
    /// @param name_ Token name (e.g. "COMPUTE").
    /// @param symbol_ Token symbol (e.g. "COMPUTE").
    /// @param admin Address that receives DEFAULT_ADMIN_ROLE and MINTER_ROLE.
    constructor(string memory name_, string memory symbol_, address admin) ERC20(name_, symbol_) {
        if (admin == address(0)) revert("ResourceToken: zero admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    /// @notice Mint resource tokens. Restricted to MINTER_ROLE.
    /// @param to Recipient address.
    /// @param amount Amount to mint (18 decimals).
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
