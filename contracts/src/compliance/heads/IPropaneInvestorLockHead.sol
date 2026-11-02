// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: interface of the issuance lock head.
// @author adiii.eth

pragma solidity 0.8.28;

import {IPropaneLockHead} from "../../interfaces/IPropaneServices.sol";

/// @title IPropaneInvestorLockHead
/// @notice Rule head, issuance hold-up: tokens still inside their lock period may not move. An independent module resolved by the engine.
interface IPropaneInvestorLockHead is IPropaneLockHead {
    function openIssuances(address wallet) external view returns (uint256);
}
