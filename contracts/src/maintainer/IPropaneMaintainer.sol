//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/*roles maintaining all the propane substrate for all upgrades*/
/// @title IPropaneMaintainer
/// @author Propane
/// @notice initial owner layer for ensuring systematic updation and regulation of propane substrate / a constraint layer essential
abstract contract IPropaneMaintainer {
    uint8 public constant NO_ROLE = 0;
    uint8 public constant SUPER_OWNER = 1;
    uint8 public constant OWNER = 2;
    uint8 public constant PROPANE = 3;
    uint8 public constant OFFICER = 4;

    event PropaneMaintainerRoleAdded(address indexed addr, uint8 role, address indexed sender);
    event PropaneMaintainerRoleRemoved(address indexed addr, address indexed sender);

    function initialize() public virtual;
    function addUniversalRole(address _addr, uint8 _role) external virtual returns (bool);
    function removeUniversalRole(address _addr) external virtual returns (bool);
    function getRoles(address _addr) public view virtual returns (uint8);
}
