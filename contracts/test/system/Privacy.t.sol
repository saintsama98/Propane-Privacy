// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/orbex/propaneEngine.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {IPropaneCensus, PropaneAttributes} from "../../src/interfaces/IPropaneServices.sol";
import {PropaneCodes} from "../../src/common/PropaneConstants.sol";
import {ebool, euint8, euint32, euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/// @notice Disclosure properties, checked against the ACL: who may decrypt
///         which handle. A handle an account is not allowed on cannot be decrypted by it.
contract PrivacyTest is PropaneFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal venue = makeAddr("venue");
    address internal stranger = makeAddr("stranger");

    function setUp() public override {
        super.setUp();
        _register(alice, US, 0, true, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
    }

    // ------------------------------------------------------------ census

    function test_censusReadableOnlyByEngineAndKeeper() public {
        _transfer(alice, bob, 10);
        IPropaneCensus.Counters memory c = census.counters();
        bytes32[5] memory hs = [
            euint32.unwrap(c.total),
            euint32.unwrap(c.accredited),
            euint32.unwrap(c.us),
            euint32.unwrap(c.usAccredited),
            euint32.unwrap(c.jp)
        ];
        for (uint256 i = 0; i < hs.length; i++) {
            assertTrue(_allowed(hs[i], keeper), "keeper reads census");
            assertTrue(_allowed(hs[i], address(engine)), "engine reads census");
            assertFalse(_allowed(hs[i], issuer), "issuer key is not the record keeper");
            assertFalse(_allowed(hs[i], alice), "holder");
            assertFalse(_allowed(hs[i], venue), "venue");
            assertFalse(_allowed(hs[i], stranger), "public");
            assertFalse(_acl.isAllowedForDecryption(hs[i]), "never publicly decryptable");
        }
    }

    // ------------------------------------------------------------ indistinguishable update

    function test_everyCounterRewrittenEvenWhenNoHolderChanges() public {
        IPropaneCensus.Counters memory before = census.counters();
        _transfer(alice, alice, 1); // self-transfer: no holder change at all
        IPropaneCensus.Counters memory afterwards = census.counters();
        assertTrue(euint32.unwrap(before.total) != euint32.unwrap(afterwards.total));
        assertTrue(euint32.unwrap(before.us) != euint32.unwrap(afterwards.us));
        assertTrue(euint32.unwrap(before.jp) != euint32.unwrap(afterwards.jp));
        _assertCensus();
    }

    function test_refusedTransferAlsoRewritesCounters() public {
        IPropaneCensus.Counters memory before = census.counters();
        _transfer(alice, bob, 1000); // refused: insufficient
        IPropaneCensus.Counters memory afterwards = census.counters();
        assertTrue(euint32.unwrap(before.total) != euint32.unwrap(afterwards.total));
    }

    // ------------------------------------------------------------ reason codes

    function test_reasonCodeOnlyToSubjectAndKeeper() public {
        _transfer(alice, bob, 1000);
        bytes32 code = euint8.unwrap(engine.lastCode(alice));
        assertEq(decrypt(engine.lastCode(alice)), PropaneCodes.CODE_NOT_ENOUGH_TOKENS);
        assertTrue(_allowed(code, alice));
        assertTrue(_allowed(code, keeper));
        assertFalse(_allowed(code, bob), "counterparty does not learn the reason");
        assertFalse(_allowed(code, issuer));
        assertFalse(_allowed(code, stranger));
    }

    function test_refusalIsNotARevert() public {
        (externalEuint64 h, bytes memory p) = encryptUint64(1000, alice, address(token));
        _nextBlock();
        vm.prank(alice);
        euint64 moved = token.confidentialTransfer(bob, h, p); // does not revert
        assertEq(decrypt(moved), 0);
    }

    // ------------------------------------------------------------ balances and amounts

    function test_balancesVisibleToHolderAndKeeperOnly() public {
        _transfer(alice, bob, 10);
        bytes32 hb = euint64.unwrap(token.confidentialBalanceOf(bob));
        assertTrue(_allowed(hb, bob));
        assertTrue(_allowed(hb, keeper));
        assertFalse(_allowed(hb, alice), "sender cannot read recipient balance");
        assertFalse(_allowed(hb, stranger));
        bytes32 supply = euint64.unwrap(token.confidentialTotalSupply());
        assertTrue(_allowed(supply, keeper));
        assertFalse(_allowed(supply, stranger), "supply not public: no differencing");
    }

    function test_attributesVisibleToKeeperNotPublic() public view {
        PropaneAttributes memory a = registry.attributes(alice);
        assertTrue(_allowed(euint8.unwrap(a.region), keeper));
        assertFalse(_allowed(euint8.unwrap(a.region), alice), "attributes are attested about, not given to, the holder");
        assertFalse(_allowed(euint8.unwrap(a.region), stranger));
        assertFalse(_allowed(ebool.unwrap(a.accredited), stranger));
    }

    // ------------------------------------------------------------ pre-check

    function test_subjectCanPrecheck() public {
        (ebool verdict, euint8 code) = _precheck(alice, alice, bob, 10);
        assertTrue(decrypt(verdict));
        assertEq(decrypt(code), PropaneCodes.CODE_VALID);
        assertTrue(_allowed(ebool.unwrap(verdict), alice));
        assertTrue(_allowed(euint8.unwrap(code), alice));
    }

    function test_strangerGetsNoAnswer() public {
        (externalEuint64 h, bytes memory p) = encryptUint64(10, stranger, address(engine));
        _nextBlock();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, stranger));
        engine.requestTransferCheck(alice, bob, h, p);
    }

    function test_delegatedVenueGetsVerdictButNotReason() public {
        vm.prank(alice);
        engine.setDelegate(venue, true);
        (ebool verdict, euint8 code) = _precheck(venue, alice, bob, 1000);
        assertFalse(decrypt(verdict));
        assertTrue(_allowed(ebool.unwrap(verdict), venue), "venue reads the verdict");
        assertFalse(_allowed(euint8.unwrap(code), venue), "venue does not read the reason");
        assertTrue(_allowed(euint8.unwrap(code), alice), "subject reads the reason");
        assertEq(decrypt(code), PropaneCodes.CODE_NOT_ENOUGH_TOKENS);
    }

    function test_revokedDelegateLosesAccess() public {
        vm.prank(alice);
        engine.setDelegate(venue, true);
        vm.prank(alice);
        engine.setDelegate(venue, false);
        (externalEuint64 h, bytes memory p) = encryptUint64(10, venue, address(engine));
        _nextBlock();
        vm.prank(venue);
        vm.expectRevert();
        engine.requestTransferCheck(alice, bob, h, p);
    }

    function test_precheckDoesNotMoveFundsOrCensus() public {
        uint32[9] memory before = _counters();
        _precheck(alice, alice, bob, 10);
        assertEq(_bal(alice), 100);
        assertEq(_bal(bob), 0);
        uint32[9] memory afterwards = _counters();
        for (uint256 k = 0; k < 9; k++) {
            assertEq(before[k], afterwards[k]);
        }
    }

    // ------------------------------------------------------------ oracle guards

    function test_engineMutatingPathsAreTokenOnly() public {
        euint64 z;
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, stranger));
        engine.validateTransfer(alice, bob, z, z);
    }

    function test_censusCapChecksAreEngineOnly() public {
        vm.prank(stranger);
        vm.expectRevert();
        census.capChecks(_emptyCapInput());
    }

    function test_tokenComputeAvailableIsEngineOnly() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, stranger));
        token.computeAvailable(alice);
    }

    function test_onlyTransferAgentRegisters() public {
        vm.expectRevert();
        vm.prank(issuer);
        registry.deregisterWallet(alice);
    }

    // ------------------------------------------------------------ helpers

    function _precheck(address caller, address from, address to, uint64 amount)
        internal
        returns (ebool verdict, euint8 code)
    {
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, caller, address(engine));
        _nextBlock();
        vm.prank(caller);
        (verdict, code) = engine.requestTransferCheck(from, to, h, p);
    }

    function _emptyCapInput() internal pure returns (PropaneCapInputAlias memory i) {
        return i;
    }
}

import {PropaneCapInput as PropaneCapInputAlias} from "../../src/interfaces/IPropaneServices.sol";
