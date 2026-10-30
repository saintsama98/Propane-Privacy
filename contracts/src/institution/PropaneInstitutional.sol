//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PropaneInstitutionalBase} from "./PropaneInstitutionalBase.sol";
import {PropaneInstitutionalStorage} from "../storage/PropaneInstitutionalStorage.sol";
import {IPropaneRoles} from "../interfaces/IPropaneServices.sol";
import {PropaneRoles, PropaneServices} from "../common/PropaneConstants.sol";
import {IPropaneInvestorEOAHead} from "../compliance/heads/IPropaneInvestorEOAHead.sol";
import {IPropaneInvestorTempBarredHead} from "../compliance/heads/IPropaneInvestorTempBarredHead.sol";
import {IPropaneInvestorWhitelistHead} from "../compliance/heads/IPropaneInvestorWhitelistHead.sol";
import {IPropaneInvestorBlacklistHead} from "../compliance/heads/IPropaneInvestorBlacklistHead.sol";

/*institutional locator | the one place every service resolves its peers*/
/// @title PropaneInstitutional
/// @author Propane
/// @notice Service locator. Services hold a reference to this contract only and resolve each other by
///         identifier at call time, so a compliance posture is changed by replacing one entry.
contract PropaneInstitutional is Initializable, UUPSUpgradeable, PropaneInstitutionalBase, PropaneInstitutionalStorage {
    error PropaneZeroMaintainer();
    error PropaneNotEnoughPermissions();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address maintainer) external initializer {
        require(maintainer != address(0), PropaneZeroMaintainer());
        _institutional().services[PropaneServices.SVC_ROLES] = maintainer;
        emit PropaneInstitutionServiceSet(PropaneServices.SVC_ROLES, maintainer);
    }

    function _roleOf(address account) internal view returns (uint8) {
        return IPropaneRoles(_institutional().services[PropaneServices.SVC_ROLES]).getRoles(account);
    }

    /// @notice Wires or replaces a service. The roles entry is replaceable by the super owner only,
    ///         because replacing it replaces every authority check in the system.
    function setInstitutionalService(uint256 serviceId, address serviceAddress) external {
        uint8 r = _roleOf(msg.sender);
        if (serviceId == PropaneServices.SVC_ROLES) {
            require(r == PropaneRoles.ROLE_SUPER_OWNER, PropaneNotEnoughPermissions());
            require(serviceAddress != address(0), PropaneZeroMaintainer());
        } else {
            require(r == PropaneRoles.ROLE_SUPER_OWNER || r == PropaneRoles.ROLE_PROPANE, PropaneNotEnoughPermissions());
        }
        _institutional().services[serviceId] = serviceAddress;
        emit PropaneInstitutionServiceSet(serviceId, serviceAddress);
    }

    function getInstitutionalService(uint256 serviceId) public view override returns (address) {
        return _institutional().services[serviceId];
    }

    function getEOAHead() public view returns (IPropaneInvestorEOAHead) {
        return IPropaneInvestorEOAHead(getInstitutionalService(EOA_HEAD));
    }

    function getBarringHead() public view returns (IPropaneInvestorTempBarredHead) {
        return IPropaneInvestorTempBarredHead(getInstitutionalService(BARRING_HEAD));
    }

    function getWhitelistingHead() public view returns (IPropaneInvestorWhitelistHead) {
        return IPropaneInvestorWhitelistHead(getInstitutionalService(WHITELISTING_HEAD));
    }

    function getBlacklistingHead() public view returns (IPropaneInvestorBlacklistHead) {
        return IPropaneInvestorBlacklistHead(getInstitutionalService(BLACKLISTING_HEAD));
    }

    function _authorizeUpgrade(address) internal view override {
        require(_roleOf(msg.sender) == PropaneRoles.ROLE_SUPER_OWNER, PropaneNotEnoughPermissions());
    }
}
