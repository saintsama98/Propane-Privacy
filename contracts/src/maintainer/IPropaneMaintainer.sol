//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {PropaneRoles} from "../common/PropaneConstants.sol";

/*roles maintaining all the propane substrate for all upgrades*/
/// @title IPropaneMaintainer
/// @author Propane
/// @notice initial owner layer for ensuring systematic updation and regulation of propane substrate / a constraint layer essential
abstract contract IPropaneMaintainer {
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
