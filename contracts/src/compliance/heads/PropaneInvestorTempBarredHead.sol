//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices} from "../../common/PropaneConstants.sol";
import {IPropaneInvestorTempBarredHead} from "./IPropaneInvestorTempBarredHead.sol";

/*investor temporary bar head | time-bounded restriction rule module for the compliance engine*/
/// @title PropaneInvestorTempBarredHead
/// @author Propane
/// @notice Bars a sender until an encrypted timestamp. The bar time is encrypted so that the
///         existence and length of a bar are not public.
contract PropaneInvestorTempBarredHead is PropaneServiceConsumer, IPropaneInvestorTempBarredHead {
    /// @custom:storage-location erc7201:propane.storage.TempBarredHead
    struct TempBarredHeadStorage {
        mapping(address wallet => euint64 until) barredUntil;
    }

    // erc7201("propane.storage.TempBarredHead")
    bytes32 private constant TEMP_BARRED_HEAD_STORAGE =
        0xb5b1265a431bbb4654fd4857424d6f1471f1c3f31f701ce56944a9125d412b00;

    event PropaneBarUpdated(address indexed wallet);

    function _store() private pure returns (TempBarredHeadStorage storage $) {
        bytes32 s = TEMP_BARRED_HEAD_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function setBarredUntil(address wallet, externalEuint64 until, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        euint64 v = FHE.fromExternal(until, proof);
        FHE.allowThis(v);
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
        _store().barredUntil[wallet] = v;
        emit PropaneBarUpdated(wallet);
    }

    function blocked(address from, address) external onlyService(PropaneServices.SVC_COMPLIANCE) returns (ebool r) {
        euint64 until = _store().barredUntil[from];
        r = FHE.isInitialized(until) ? FHE.gt(until, uint64(block.timestamp)) : FHE.asEbool(false);
        FHE.allowTransient(r, msg.sender);
    }
}
