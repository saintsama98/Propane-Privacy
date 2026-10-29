// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/engine/PropaneComplianceEngine.sol";

/// @notice Census invariant under arbitrary operation sequences: after every operation, each
///         encrypted counter equals the count recomputed in the clear from balances and attributes.
///         Then the on-chain recomputation must reproduce the live census exactly.
contract CensusSequenceTest is PropaneFixture {
    address[6] internal w;

    function _config() internal view override returns (PropaneComplianceEngine.Config memory c) {
        c = super._config();
        c.limits.euCountrySlots = 2;
        // Caps enabled but loose, so the census rules run on every transfer without blocking it.
        c.limits.totalInvestorsLimit = 1000;
        c.limits.maxUSInvestorsPercentage = 90;
        c.limits.jpInvestorsLimit = 1000;
        c.limits.euRetailInvestorsLimit = 1000;
    }

    function setUp() public override {
        super.setUp();
        uint8[6] memory regions = [US, US, EU, EU, JP, OTHER];
        for (uint256 i = 0; i < 6; i++) {
            w[i] = makeAddr(string.concat("w", vm.toString(i)));
            _register(w[i], regions[i], uint8(i % 2), i % 3 == 0, i == 3);
        }
        _issue(w[0], 50);
        _issue(w[2], 50);
    }

    /// forge-config: default.fuzz.runs = 12
    function testFuzz_censusMatchesTruth(uint256 seed) public {
        for (uint256 step = 0; step < 10; step++) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 op = seed % 8;
            address x = w[(seed >> 8) % 6];
            address y = w[(seed >> 16) % 6];
            uint64 amt = uint64((seed >> 24) % 60);
            if (op <= 3) {
                _transfer(x, y, amt);
            } else if (op == 4) {
                _issue(x, amt);
            } else if (op == 5) {
                _burn(x, amt);
            } else if (op == 6) {
                if (x != y) _forced(x, y, amt);
            } else {
                uint8[4] memory r = [US, EU, JP, OTHER];
                _update(x, r[(seed >> 32) % 4], uint8((seed >> 40) % 2), (seed >> 48) % 2 == 0, (seed >> 56) % 2 == 0);
            }
            _assertCensus();
        }

        uint32[9] memory live = _counters();
        _recompute();
        uint32[9] memory recomputed = _counters();
        for (uint256 k = 0; k < 9; k++) {
            assertEq(recomputed[k], live[k], "recompute reproduces live census");
        }
    }

    function test_recomputeRepairsADriftedCensus() public {
        // Drift the census deliberately: a counted holder is flagged as a platform wallet and exits
        // while flagged, so its exit is never counted (the documented hazard of setPlatformWallet).
        _nextBlock();
        vm.prank(operator);
        engine.setPlatformWallet(w[0], true);
        _transfer(w[0], w[5], 50);
        _nextBlock();
        vm.prank(operator);
        engine.setPlatformWallet(w[0], false);
        uint32[9] memory drifted = _counters();
        uint32[9] memory want = _expectedCounters();
        assertEq(drifted[0], want[0] + 1, "census over-counts by the uncounted exit");
        // Recomputation from chain state repairs it without trusting whoever triggers it.
        _recompute();
        _assertCensus();
    }

    /// @dev Recompute in batches of RECOMPUTE_BATCH wallets, one batch per block.
    uint256 internal constant RECOMPUTE_BATCH = 2;

    function _recompute() internal {
        _nextBlock();
        vm.prank(ta);
        census.beginRecompute();
        for (uint256 i = 0; i < known.length; i += RECOMPUTE_BATCH) {
            _nextBlock();
            census.continueRecompute(RECOMPUTE_BATCH);
        }
        _nextBlock();
        vm.prank(ta);
        census.finishRecompute();
    }

    function test_recomputeRequiresCompletion() public {
        vm.prank(ta);
        census.beginRecompute();
        census.continueRecompute(2);
        vm.prank(ta);
        vm.expectRevert("Recompute incomplete");
        census.finishRecompute();
    }
}
