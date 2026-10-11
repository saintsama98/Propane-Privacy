//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IPropaneLocator, IPropaneRoles} from "../interfaces/IPropaneServices.sol";
import {PropaneRoles, PropaneServices} from "./PropaneConstants.sol";

/*service consumer | resolves peers through the institutional locator and authority through the maintainer*/
/// @title PropaneServiceConsumer
/// @author Propane
/// @notice Base for every upgradeable Propane service. Holds one reference, to the locator, and
///         resolves every other service at call time, so any service can be replaced without
///         touching the others (the prior art's service-locator pattern).
abstract contract PropaneServiceConsumer is Initializable, UUPSUpgradeable {
    /// @custom:storage-location erc7201:propane.storage.ServiceConsumer
    struct ServiceConsumerStorage {
        address locator;
    }

    // erc7201("propane.storage.ServiceConsumer")
    bytes32 private constant SERVICE_CONSUMER_STORAGE =
        0xcde2cd6f018bac2565ea68cf7cec757db4499fb88bae5238ef9de757484f1700;

    error PropaneUnauthorized(address caller);
    error PropaneServiceMissing(uint256 serviceId);

    event PropaneLocatorSet(address indexed locator);

    function _consumer() private pure returns (ServiceConsumerStorage storage $) {
        bytes32 s = SERVICE_CONSUMER_STORAGE;
        assembly {
            $.slot := s
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Also binds the FHE coprocessor for the current chain. The binding lives in the proxy's
    ///      storage, which is why it is done here and not in a constructor.
    function __PropaneServiceConsumer_init(address locator_) internal onlyInitializing {
        require(locator_ != address(0), "Zero locator");
        _consumer().locator = locator_;
        FHE.setCoprocessor(ZamaConfig.getEthereumCoprocessorConfig());
        emit PropaneLocatorSet(locator_);
    }

    function locator() public view returns (address) {
        return _consumer().locator;
    }

    function _serviceOrZero(uint256 serviceId) internal view returns (address) {
        return IPropaneLocator(_consumer().locator).getInstitutionalService(serviceId);
    }

    function _service(uint256 serviceId) internal view returns (address s) {
        s = _serviceOrZero(serviceId);
        if (s == address(0)) revert PropaneServiceMissing(serviceId);
    }

    function _roleOf(address account) internal view returns (uint8) {
        return IPropaneRoles(_service(PropaneServices.SVC_ROLES)).getRoles(account);
    }

    function _recordKeeper() internal view returns (address) {
        return _serviceOrZero(PropaneServices.SVC_RECORD_KEEPER);
    }

    modifier onlyRoles2(uint8 a, uint8 b) {
        uint8 r = _roleOf(msg.sender);
        if (r != a && r != b) revert PropaneUnauthorized(msg.sender);
        _;
    }

    modifier onlyService(uint256 serviceId) {
        if (msg.sender != _service(serviceId)) revert PropaneUnauthorized(msg.sender);
        _;
    }

    function _authorizeUpgrade(address) internal virtual override {
        if (_roleOf(msg.sender) != PropaneRoles.ROLE_SUPER_OWNER) revert PropaneUnauthorized(msg.sender);
    }
}
