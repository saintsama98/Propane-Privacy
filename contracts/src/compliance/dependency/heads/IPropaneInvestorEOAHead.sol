//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IPropaneRuleHead} from "../../../interfaces/IPropaneServices.sol";

/// @title IPropaneInvestorEOAHead
/// @author Propane
/// @notice Rule head, account-shape rule: the recipient must be an externally owned account unless it is a platform wallet. An independent module resolved by the engine.
interface IPropaneInvestorEOAHead is IPropaneRuleHead {}
