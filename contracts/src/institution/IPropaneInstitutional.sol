//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {PropaneServices} from "../common/PropaneConstants.sol";

abstract contract IPropaneInstitutional {
    //service named keys (minimal for now)

    uint256 public constant ROLE_SERVICE_PROVIDER = PropaneServices.SVC_ROLES;
    uint256 public constant REGISTRY_SERVICE_PROVIDER = PropaneServices.SVC_REGISTRY;
    uint256 public constant LOCK_HEAD = PropaneServices.SVC_LOCK_HEAD;
    uint256 public constant BARRING_HEAD = PropaneServices.SVC_BARRING_HEAD;
    uint256 public constant WHITELISTING_HEAD = PropaneServices.SVC_WHITELISTING_HEAD;
    uint256 public constant BLACKLISTING_HEAD = PropaneServices.SVC_BLACKLISTING_HEAD;
    uint256 public constant COMPLIANCE_HEAD = PropaneServices.SVC_COMPLIANCE;
    uint256 public constant EOA_HEAD = PropaneServices.SVC_EOA_HEAD;
    uint256 public constant TOKEN_SERVICE = PropaneServices.SVC_TOKEN;
    uint256 public constant RECORD_KEEPER = PropaneServices.SVC_RECORD_KEEPER;

    event PropaneInstitutionServiceSet(uint256 indexed serviceId, address indexed serviceAddress);

    function getInstitutionalService(uint256 serviceId) public view virtual returns (address);
}

