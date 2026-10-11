//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, externalEbool} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices} from "../../../common/PropaneConstants.sol";
import {IPropaneInvestorBlacklistHead} from "./IPropaneInvestorBlacklistHead.sol";

/*investor blacklist head | denied-investor rule module for the compliance engine*/
/// @title PropaneInvestorBlacklistHead
/// @author Propane
/// @notice Encrypted deny list. Blocks a listed sender as well as a listed recipient: a sanctions
///         listing overrides the sender-exit property (Note 05, R17) by design.
contract PropaneInvestorBlacklistHead is PropaneServiceConsumer, IPropaneInvestorBlacklistHead {
    /// @custom:storage-location erc7201:propane.storage.BlacklistHead
    struct BlacklistHeadStorage {
        mapping(address wallet => ebool listed) listed;
    }

    // erc7201("propane.storage.BlacklistHead")
    bytes32 private constant BLACKLIST_HEAD_STORAGE =
        0x5c58693a7f160a23b5d1814abc2874e69bc93e8995fa236d1b6bb5d480443c00;

    event PropaneBlacklistUpdated(address indexed wallet);

    function _store() private pure returns (BlacklistHeadStorage storage $) {
        bytes32 s = BLACKLIST_HEAD_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function setBlacklisted(address wallet, externalEbool listed, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        ebool v = FHE.fromExternal(listed, proof);
        FHE.allowThis(v);
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
        _store().listed[wallet] = v;
        emit PropaneBlacklistUpdated(wallet);
    }

    function blocked(address from, address to) external onlyService(PropaneServices.SVC_COMPLIANCE) returns (ebool r) {
        BlacklistHeadStorage storage $ = _store();
        r = FHE.or(_flag($.listed[from]), _flag($.listed[to]));
        FHE.allowTransient(r, msg.sender);
    }

    function _flag(ebool v) private returns (ebool) {
        return FHE.isInitialized(v) ? v : FHE.asEbool(false);
    }
}
