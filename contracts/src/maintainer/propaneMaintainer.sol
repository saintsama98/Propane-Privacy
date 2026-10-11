//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IPropaneMaintainer} from "./IPropaneMaintainer.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract PropaneMaintainer is Initializable, UUPSUpgradeable, IPropaneMaintainer {
    /*roles maintaining all the propane substrate for all upgrades*/
    // @title A title that should describe the contract/interface
    /// @author Propane
    /// @notice initial owner layer for ensuring systematic updation and regulation of propane substrate / a constraint layer essential

    /// @custom:storage-location erc7201:propane.storage.Maintainer
    struct MaintainerStorage {
        address owner;
        mapping(address account => uint8 role) roles;
    }

    // erc7201("propane.storage.Maintainer")
    bytes32 private constant MAINTAINER_STORAGE = 0xecd650e130efcdb91f813bdd8d63149ee409488eac16480924c5e3846af82f00;

    /// @dev `storage` here is an alias, not a copy. Declaring it `memory` would
    ///      silently discard every write.
    function _maintainer() private pure returns (MaintainerStorage storage $) {
        bytes32 s = MAINTAINER_STORAGE;
        assembly {
            $.slot := s
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize() public override initializer {
        MaintainerStorage storage $ = _maintainer();
        $.owner = msg.sender;
        //update storage
        $.roles[msg.sender] = SUPER_OWNER;
    }

    //role based modifers | level essentials

    modifier onlySuperOwner() {
        require(_maintainer().roles[msg.sender] == SUPER_OWNER, "Not enough permissions");
        _;
    }

    modifier onlySuperOwnerOrPropane() {
        require(
            _maintainer().roles[msg.sender] == SUPER_OWNER || _maintainer().roles[msg.sender] == PROPANE,
            "Not enough permissions"
        );
        _;
    }

    modifier onlySuperOwnerOrPropaneOrOfficer() {
        require(
            _maintainer().roles[msg.sender] == SUPER_OWNER || _maintainer().roles[msg.sender] == PROPANE
                || _maintainer().roles[msg.sender] == OFFICER,
            "Not enough permissions"
        );
        _;
    }

    //maintainer substrate functions
    ///@notice substrate functions are meant to be having purpose as present in every core layer/module of this application

    //adds role to roles[]

    function addUniversalRole(address _addr, uint8 _role)
        external
        override
        onlySuperOwnerOrPropaneOrOfficer
        returns (bool)
    {
        require(_role == OWNER || _role == PROPANE || _role == OFFICER, "No such authority provided");
        _requireCanManage(_maintainer().roles[_addr], _role);
        _setRole(_addr, _role);
        return true;
    }

    /// @dev Scope of a role-management call, equivalent to the prior art's
    ///      `onlySameRole` and `onlySameRoleForAddress` guards. SUPER_OWNER may
    ///      manage any address except its own entry. Any other caller may only
    ///      grant or remove its own role, and only on an address that holds no
    ///      role or that same role. Without this, OFFICER could grant OWNER or
    ///      overwrite the SUPER_OWNER entry and lock upgrades permanently.
    function _requireCanManage(uint8 _targetRole, uint8 _newRole) internal view {
        require(_targetRole != SUPER_OWNER, "Cannot modify super owner");
        uint8 callerRole = _maintainer().roles[msg.sender];
        if (callerRole == SUPER_OWNER) return;
        require(_newRole == callerRole, "Only same role allowed");
        require(_targetRole == NO_ROLE || _targetRole == callerRole, "Only same role allowed");
    }

    /// @dev Direct role-to-role transitions are permitted deliberately. The prior
    ///      art requires NO_ROLE as an intermediate step, which leaves a window in
    ///      which the address holds nothing; that is a defect, not a safeguard.
    ///      The log stays complete because a change emits Removed then Added.
    function _setRole(address _addr, uint8 _role) internal {
        MaintainerStorage storage $ = _maintainer();
        uint8 prev_role = $.roles[_addr];
        if (prev_role == _role) return;

        $.roles[_addr] = _role;

        if (prev_role != NO_ROLE) {
            emit PropaneMaintainerRoleRemoved(_addr, msg.sender);
        }
        if (_role != NO_ROLE) {
            emit PropaneMaintainerRoleAdded(_addr, _role, msg.sender);
        }
    }

    function removeUniversalRole(address _addr) external override onlySuperOwnerOrPropaneOrOfficer returns (bool) {
        uint8 role = _maintainer().roles[_addr];

        // `&&`, not `||`: any value differs from at least one of two distinct
        // constants, so the disjunction can never revert.
        require(role != SUPER_OWNER && role != OWNER, "Role cannot be removed");
        _requireCanManage(role, role);
        _setRole(_addr, NO_ROLE);
        return true;
    }

    /// @notice Moves SUPER_OWNER in a single transaction. The only path by which
    ///         SUPER_OWNER can ever change: `addUniversalRole` rejects it, and
    ///         `removeUniversalRole` refuses to strip it.
    function transferSuperOwner(address _newOwner) external override onlySuperOwner returns (bool) {
        require(_newOwner != address(0), "Zero address");
        require(_newOwner != msg.sender, "Already super owner");

        MaintainerStorage storage $ = _maintainer();
        require($.roles[_newOwner] == NO_ROLE, "Target already holds a role");

        _setRole(msg.sender, NO_ROLE);
        _setRole(_newOwner, SUPER_OWNER);
        $.owner = _newOwner;

        emit PropaneMaintainerSuperOwnerTransferred(msg.sender, _newOwner);
        return true;
    }

    function superOwner() public view override returns (address) {
        return _maintainer().owner;
    }

    function getRoles(address _addr) public view override returns (uint8) {
        return _maintainer().roles[_addr];
    }

    /// @dev `virtual` so a deployment can tighten upgrade authority to a timelock
    ///      or multisig. The prior art omits this and the authority is frozen.
    function _authorizeUpgrade(address) internal virtual override onlySuperOwner {}
}
