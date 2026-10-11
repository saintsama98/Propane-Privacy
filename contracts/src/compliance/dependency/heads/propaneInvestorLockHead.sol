//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../../common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../../common/PropaneConstants.sol";
import {IPropaneCompliance, IPropaneLockHead} from "../../../interfaces/IPropaneServices.sol";

/*investor lock head | issuance lock records and the hold-up rule*/
/// @title PropaneInvestorLockHead
/// @author Propane
/// @notice Records each issuance with its encrypted amount and public timestamp (issuance is a public
///         event), and answers whether a transfer would draw on tokens still inside their lock
///         period. The lock period depends on the sender's encrypted region, so each record
///         contributes a select between its US and non-US lock state.
contract PropaneInvestorLockHead is PropaneServiceConsumer, IPropaneLockHead {
    uint256 public constant MAX_OPEN_ISSUANCES = 8;

    struct Issuance {
        euint64 amount;
        uint64 time;
    }

    /// @custom:storage-location erc7201:propane.storage.LockHead
    struct LockHeadStorage {
        mapping(address wallet => Issuance[]) issuances;
    }

    // erc7201("propane.storage.LockHead")
    bytes32 private constant LOCK_HEAD_STORAGE = 0x7de80d05f185b2a0514c2cf3e56c3945fcc80c97bc4061ac56420d13059dec00;

    function _l() private pure returns (LockHeadStorage storage $) {
        bytes32 s = LOCK_HEAD_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function openIssuances(address wallet) external view returns (uint256) {
        return _l().issuances[wallet].length;
    }

    function recordIssuance(address to, euint64 amount) external onlyService(PropaneServices.SVC_COMPLIANCE) {
        (uint64 usLock, uint64 nonUSLock) = IPropaneCompliance(msg.sender).lockPeriods();
        if (usLock == 0 && nonUSLock == 0) return;
        Issuance[] storage iss = _l().issuances[to];
        uint64 longest = usLock > nonUSLock ? usLock : nonUSLock;
        // Drop records whose every lock has expired; order is irrelevant to the lock sum.
        for (uint256 i = iss.length; i > 0; i--) {
            if (iss[i - 1].time + longest <= block.timestamp) {
                iss[i - 1] = iss[iss.length - 1];
                iss.pop();
            }
        }
        require(iss.length < MAX_OPEN_ISSUANCES, "Too many open issuances");
        FHE.allowThis(amount);
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(amount, keeper);
        iss.push(Issuance({amount: amount, time: uint64(block.timestamp)}));
    }

    function lockedFails(address from, ebool fromUS, euint64 available, euint64 amount)
        external
        onlyService(PropaneServices.SVC_COMPLIANCE)
        returns (ebool f)
    {
        (uint64 usLock, uint64 nonUSLock) = IPropaneCompliance(msg.sender).lockPeriods();
        Issuance[] storage iss = _l().issuances[from];
        euint64 locked = FHE.asEuint64(0);
        for (uint256 i = 0; i < iss.length; i++) {
            bool lockedUS = iss[i].time + usLock > block.timestamp;
            bool lockedNonUS = iss[i].time + nonUSLock > block.timestamp;
            if (lockedUS && lockedNonUS) {
                locked = FHE.add(locked, iss[i].amount);
            } else if (lockedUS || lockedNonUS) {
                ebool applies = lockedUS ? fromUS : FHE.not(fromUS);
                locked = FHE.add(locked, FHE.select(applies, iss[i].amount, FHE.asEuint64(0)));
            }
        }
        euint64 transferable = FHE.select(FHE.ge(available, locked), FHE.sub(available, locked), FHE.asEuint64(0));
        f = FHE.lt(transferable, amount);
        FHE.allowTransient(f, msg.sender);
    }
}
