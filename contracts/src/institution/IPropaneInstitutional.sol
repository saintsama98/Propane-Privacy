//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

abstract contract IPropaneInstitutional {
    //service named keys (minimal for now)

    uint256 public constant ROLE_SERVICE_PROVIDER = 1;
    uint256 public constant REGISTRY_SERVICE_PROVIDER = 2;
    uint256 public constant LOCK_HEAD = 4;
    uint256 public constant BARRING_HEAD = 5;
    uint256 public constant WHITELISTING_HEAD = 6;
    uint256 public constant BLACKLISTING_HEAD = 7;
    uint256 public constant COMPLIANCE_HEAD = 8;
    uint256 public constant EOA_HEAD = 9;

    event PropaneInstitutionServiceSet(uint256 serviceId, address serviceAddress);

    function getInstitutionalService(uint256 serviceId) public view virtual returns (address);
}

