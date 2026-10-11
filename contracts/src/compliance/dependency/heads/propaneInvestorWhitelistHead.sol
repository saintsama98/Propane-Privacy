//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, externalEbool} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices} from "../../../common/PropaneConstants.sol";
import {IPropaneInvestorWhitelistHead} from "./IPropaneInvestorWhitelistHead.sol";

/*investor whitelist head | admitted-investor rule module for the compliance engine*/
/// @title PropaneInvestorWhitelistHead
/// @author Propane
/// @notice Offering-level admission on top of registry registration: a recipient must hold an
///         encrypted admission flag set by the issuer. Admission is not public.
contract PropaneInvestorWhitelistHead is PropaneServiceConsumer, IPropaneInvestorWhitelistHead {
    /// @custom:storage-location erc7201:propane.storage.WhitelistHead
    struct WhitelistHeadStorage {
        mapping(address wallet => ebool admitted) admitted;
    }

    // erc7201("propane.storage.WhitelistHead")
    bytes32 private constant WHITELIST_HEAD_STORAGE =
        0x254fa7182b3326ce6540f2a83f73334fae8ff412261280697c8ae19ab0d69400;

    event PropaneAdmissionUpdated(address indexed wallet);

    function _store() private pure returns (WhitelistHeadStorage storage $) {
        bytes32 s = WHITELIST_HEAD_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function setAdmitted(address wallet, externalEbool admitted, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OWNER, PropaneRoles.ROLE_OFFICER)
    {
        ebool v = FHE.fromExternal(admitted, proof);
        FHE.allowThis(v);
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
        _store().admitted[wallet] = v;
        emit PropaneAdmissionUpdated(wallet);
    }

    function blocked(address, address to) external onlyService(PropaneServices.SVC_COMPLIANCE) returns (ebool r) {
        ebool a = _store().admitted[to];
        r = FHE.isInitialized(a) ? FHE.not(a) : FHE.asEbool(true);
        FHE.allowTransient(r, msg.sender);
    }
}
