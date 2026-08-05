//SPDX-License-Identifier: MIT

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
        require(_maintainer().roles[msg.sender] == SUPER_OWNER);
        _;
    }

    modifier onlySuperOwnerOrPorpane() {
        require(_maintainer().roles[msg.sender] == SUPER_OWNER || _maintainer().roles[msg.sender] == PROPANE);
        _;
    }

    modifier onlySuperOwnerOrPorpaneOrOfficer() {
        require(
            _maintainer().roles[msg.sender] == SUPER_OWNER || _maintainer().roles[msg.sender] == PROPANE
                || _maintainer().roles[msg.sender] == OFFICER
        );
        _;
    }

    //maintainer substrate functions
    ///@notice substrate functions are meant to be having purpose as present in every core layer/module of this application

    //adds role to roles[]

    function addUniversalRole(address _addr, uint8 _role)
        external
        override
        onlySuperOwnerOrPorpaneOrOfficer
        returns (bool)
    {
        require(_role == OWNER || _role == PROPANE || _role == OFFICER, "No such authority provided");
        _setRole(_addr, _role);
        return true;
    }

    function _setRole(address _addr, uint8 _role) internal {
        MaintainerStorage storage $ = _maintainer();
        uint8 prev_role = $.roles[_addr];
        require(prev_role == NO_ROLE || _role == NO_ROLE);

        $.roles[_addr] = _role;
        if (prev_role == NO_ROLE) {
            emit PropaneMaintainerRoleAdded(_addr, _role, msg.sender);
        } else {
            emit PropaneMaintainerRoleRemoved(_addr, msg.sender);
        }
    }

    function removeUniversalRole(address _addr) external override returns (bool) {
        uint8 role = _maintainer().roles[_addr];

        require(role != SUPER_OWNER || role != OWNER);
        _setRole(_addr, NO_ROLE);
    }

    function getRoles(address _addr) public view override returns (uint8) {
        return _maintainer().roles[_addr];
    }
}
