//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ebool, euint8, euint32, euint64} from "encrypted-types/EncryptedTypes.sol";

/// @notice Encrypted attestation record of one wallet. One wallet is one investor in this revision.
struct PropaneAttributes {
    euint8 region;
    euint8 euCountry;
    ebool accredited;
    ebool qualified;
    ebool liquidateOnly;
}

/// @notice Census-relevant limits of the rulebook. Public by design: they describe the offering, not any investor.
struct PropaneCensusLimits {
    uint32 totalInvestorsLimit;
    uint32 minimumTotalInvestors;
    uint32 usInvestorsLimit;
    uint32 maxUSInvestorsPercentage;
    uint32 usAccreditedInvestorsLimit;
    uint32 nonAccreditedInvestorsLimit;
    uint32 jpInvestorsLimit;
    uint32 euRetailInvestorsLimit;
    uint8 euCountrySlots;
}

/// @notice Encrypted facts about both parties that the census rules need. Lent transiently by the
///         engine to the census for one evaluation.
struct PropaneCapInput {
    ebool fromUS;
    ebool fromEU;
    ebool fromAccredited;
    ebool fromQualified;
    ebool fromPartial;
    ebool fromFull;
    euint8 fromRegion;
    euint8 fromEuCountry;
    ebool toUS;
    ebool toEU;
    ebool toJP;
    ebool toAccredited;
    ebool toQualified;
    ebool toNew;
    euint8 toEuCountry;
    /// @dev Issuance applies the absolute US limit only, as in the prior art.
    bool isIssuance;
}

/// @title IPropaneLocator
/// @notice Read surface of the institutional service locator.
interface IPropaneLocator {
    function getInstitutionalService(uint256 serviceId) external view returns (address);
}

/// @title IPropaneRoles
/// @notice Read surface of the maintainer.
interface IPropaneRoles {
    function getRoles(address account) external view returns (uint8);
    function superOwner() external view returns (address);
}

/// @title IPropaneRegistry
/// @notice Confidential investor registry. Registration is public (a wallet belongs to some verified
///         investor); every attribute is encrypted. No personal data is stored, hashed or otherwise.
interface IPropaneRegistry {
    function isRegistered(address wallet) external view returns (bool);
    function attributes(address wallet) external view returns (PropaneAttributes memory);
}

/// @title IPropaneCompliance
/// @notice Compliance service. Mutating paths are callable only by the token or the registry.
interface IPropaneCompliance {
    function validateTransfer(address from, address to, euint64 amount, euint64 available)
        external
        returns (euint64 effective);
    function validateIssuance(address to, euint64 amount) external returns (euint64 effective);
    function validateBurn(address from, euint64 amount, euint64 balance) external returns (euint64 effective);
    function validateForcedTransfer(address from, address to, euint64 amount, euint64 balance)
        external
        returns (euint64 effective);
    function onAttributesChanged(address wallet, PropaneAttributes calldata previous, PropaneAttributes calldata next)
        external;
    function isPlatformWallet(address wallet) external view returns (bool);
    function euCountrySlots() external view returns (uint8);
    function censusLimits() external view returns (PropaneCensusLimits memory);
    function lockPeriods() external view returns (uint64 usLockPeriod, uint64 nonUSLockPeriod);
}

/// @title IPropaneCensus
/// @notice Confidential investor census. Counters are encrypted and readable only by the compliance
///         service and the record keeper.
interface IPropaneCensus {
    struct Counters {
        euint32 total;
        euint32 accredited;
        euint32 us;
        euint32 usAccredited;
        euint32 jp;
        euint32[4] euRetail;
    }

    function counters() external view returns (Counters memory);

    /// @notice Evaluates the investor-count cap rules against the live counters. Returns three flags,
    ///         each true when the corresponding group fails: regional caps (JP, EU retail, US, US
    ///         accredited), global caps (non-accredited, total), and the minimum-investor rule.
    function capChecks(PropaneCapInput calldata input) external returns (ebool regional, ebool global, ebool tooFew);
    function applyMove(
        PropaneAttributes calldata leaveAttrs,
        PropaneAttributes calldata enterAttrs,
        ebool leave,
        ebool enter
    ) external;
}

/// @title IPropaneLockHead
/// @notice Issuance lock records and the hold-up rule.
interface IPropaneLockHead {
    function recordIssuance(address to, euint64 amount) external;
    function lockedFails(address from, ebool fromUS, euint64 available, euint64 amount) external returns (ebool);
}

/// @title IPropaneRuleHead
/// @notice An independent rule module. Returns an encrypted flag that is true when the operation is
///         blocked, and grants the caller transient access to it.
interface IPropaneRuleHead {
    function blocked(address from, address to) external returns (ebool);
}
