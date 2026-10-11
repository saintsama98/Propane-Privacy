//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @title PropaneRoles
/// @notice Trust levels held in the maintainer. One numbering, imported everywhere.
/// @dev Mapping to the prior art: SUPER_OWNER is the master; OWNER is the issuer; PROPANE is the
///      platform operator that wires services; OFFICER is the transfer agent, which keeps the record,
///      writes the registry and holds enforcement powers.
library PropaneRoles {
    uint8 internal constant ROLE_NONE = 0;
    uint8 internal constant ROLE_SUPER_OWNER = 1;
    uint8 internal constant ROLE_OWNER = 2;
    uint8 internal constant ROLE_PROPANE = 3;
    uint8 internal constant ROLE_OFFICER = 4;
}

/// @title PropaneServices
/// @notice Service identifiers resolved through the institutional locator.
library PropaneServices {
    uint256 internal constant SVC_ROLES = 1;
    uint256 internal constant SVC_REGISTRY = 2;
    uint256 internal constant SVC_TOKEN = 3;
    uint256 internal constant SVC_LOCK_HEAD = 4;
    uint256 internal constant SVC_BARRING_HEAD = 5;
    uint256 internal constant SVC_WHITELISTING_HEAD = 6;
    uint256 internal constant SVC_BLACKLISTING_HEAD = 7;
    uint256 internal constant SVC_COMPLIANCE = 8;
    uint256 internal constant SVC_EOA_HEAD = 9;
    /// @dev Not a contract: the transfer agent's record-keeping key, granted decryption rights on
    ///      every confidential handle the system creates.
    uint256 internal constant SVC_RECORD_KEEPER = 10;
    uint256 internal constant SVC_CENSUS = 11;
}

/// @title PropaneRegions
/// @notice Regulatory region of an investor. Stored encrypted; never published.
library PropaneRegions {
    uint8 internal constant REGION_NONE = 0;
    uint8 internal constant REGION_US = 1;
    uint8 internal constant REGION_EU = 2;
    uint8 internal constant REGION_JP = 3;
    uint8 internal constant REGION_OTHER = 4;
    uint8 internal constant REGION_FORBIDDEN = 5;
}

/// @title PropaneCodes
/// @notice Reason codes. Numbering follows the prior art so that behaviour can be compared rule by
///         rule. A code is disclosed only to the subject and the transfer agent.
library PropaneCodes {
    uint8 internal constant CODE_VALID = 0;
    uint8 internal constant CODE_NOT_ENOUGH_TOKENS = 15;
    uint8 internal constant CODE_NOT_REGISTERED = 20;
    uint8 internal constant CODE_FLOWBACK = 25;
    uint8 internal constant CODE_DESTINATION_RESTRICTED = 26;
    uint8 internal constant CODE_HOLD_UP_US = 32;
    uint8 internal constant CODE_HOLD_UP = 33;
    uint8 internal constant CODE_MAX_INVESTORS_IN_CATEGORY = 40;
    uint8 internal constant CODE_ONLY_FULL_TRANSFER = 50;
    uint8 internal constant CODE_UNDER_MIN = 51;
    uint8 internal constant CODE_ABOVE_MAX = 52;
    uint8 internal constant CODE_ONLY_ACCREDITED = 61;
    uint8 internal constant CODE_ONLY_US_ACCREDITED = 62;
    uint8 internal constant CODE_NOT_ENOUGH_INVESTORS = 71;
    uint8 internal constant CODE_LIQUIDATE_ONLY = 90;
    uint8 internal constant CODE_HEAD_BLOCKED = 95;
}
