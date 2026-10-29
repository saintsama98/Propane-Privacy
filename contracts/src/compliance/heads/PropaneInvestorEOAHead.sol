//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../common/PropaneConstants.sol";
import {IPropaneInvestorEOAHead} from "./IPropaneInvestorEOAHead.sol";
import {IPropaneCompliance} from "../../interfaces/IPropaneServices.sol";

/*investor EOA head | account-shape rule module for the compliance engine*/
/// @title PropaneInvestorEOAHead
/// @author Propane
/// @notice Blocks a recipient that has code unless it is a platform wallet. Account shape is public
///         chain state, so the verdict is computed in the clear and lifted to an encrypted flag
///         only so that it combines with the encrypted ladder.
contract PropaneInvestorEOAHead is PropaneServiceConsumer, IPropaneInvestorEOAHead {
    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function blocked(address, address to) external onlyService(PropaneServices.SVC_COMPLIANCE) returns (ebool r) {
        bool isPlatform = IPropaneCompliance(msg.sender).isPlatformWallet(to);
        r = FHE.asEbool(to.code.length > 0 && !isPlatform);
        FHE.allowTransient(r, msg.sender);
    }
}
