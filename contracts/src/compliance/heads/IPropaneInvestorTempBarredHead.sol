//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IPropaneRuleHead} from "../../interfaces/IPropaneServices.sol";
import {externalEbool, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/// @title IPropaneInvestorTempBarredHead
/// @author Propane
/// @notice Rule head, time-bounded restriction: the sender is barred until an encrypted time. An independent module resolved by the engine.
interface IPropaneInvestorTempBarredHead is IPropaneRuleHead {
    function setBarredUntil(address wallet, externalEuint64 until, bytes calldata proof) external;
}
