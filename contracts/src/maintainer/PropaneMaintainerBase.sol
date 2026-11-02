// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: role constants and the external surface of the maintainer.
// @author adiii.eth

pragma solidity 0.8.28;

import {PropaneRoles} from "../common/PropaneConstants.sol";

/// @title PropaneMaintainerBase
/// @notice Role constants and the external surface of the maintainer.
abstract contract PropaneMaintainerBase {
    uint8 public constant NO_ROLE = PropaneRoles.ROLE_NONE;
    uint8 public constant SUPER_OWNER = PropaneRoles.ROLE_SUPER_OWNER;
    uint8 public constant OWNER = PropaneRoles.ROLE_OWNER;
    uint8 public constant PROPANE = PropaneRoles.ROLE_PROPANE;
    uint8 public constant OFFICER = PropaneRoles.ROLE_OFFICER;

    event PropaneMaintainerRoleAdded(address indexed addr, uint8 role, address indexed sender);
    event PropaneMaintainerRoleRemoved(address indexed addr, address indexed sender);
    event PropaneMaintainerSuperOwnerTransferred(address indexed from, address indexed to);

    function initialize() public virtual;
    function addUniversalRole(address _addr, uint8 _role) external virtual returns (bool);
    function removeUniversalRole(address _addr) external virtual returns (bool);
    function transferSuperOwner(address _newOwner) external virtual returns (bool);
    function superOwner() public view virtual returns (address);
    function getRoles(address _addr) public view virtual returns (uint8);
}
