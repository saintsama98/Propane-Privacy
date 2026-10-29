// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FheType} from "forge-fhevm/fhevm-host/contracts/shared/FheType.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    ebool,
    euint8,
    euint32,
    euint64,
    externalEbool,
    externalEuint8,
    externalEuint64
} from "encrypted-types/EncryptedTypes.sol";

import {PropaneMaintainerService} from "../../src/maintainer/PropaneMaintainerService.sol";
import {PropaneInstitutional} from "../../src/institution/PropaneInstitutional.sol";
import {PropaneComplianceRegistry} from "../../src/registry/PropaneComplianceRegistry.sol";
import {IPropaneComplianceRegistry} from "../../src/registry/IPropaneComplianceRegistry.sol";
import {PropaneComplianceEngine} from "../../src/compliance/engine/PropaneComplianceEngine.sol";
import {PropaneCensus} from "../../src/compliance/census/PropaneCensus.sol";
import {PropaneInvestorLockHead} from "../../src/compliance/heads/PropaneInvestorLockHead.sol";
import {PropaneSecurityToken} from "../../src/security/PropaneSecurityToken.sol";
import {IPropaneCensus, PropaneCensusLimits} from "../../src/interfaces/IPropaneServices.sol";
import {PropaneRoles, PropaneServices, PropaneRegions} from "../../src/common/PropaneConstants.sol";

/// @notice Deploys the whole system behind UUPS proxies on the fhEVM host contracts.
abstract contract PropaneFixture is FhevmTest {
    PropaneMaintainerService internal maintainer;
    PropaneInstitutional internal loc;
    PropaneComplianceRegistry internal registry;
    PropaneComplianceEngine internal engine;
    PropaneCensus internal census;
    PropaneInvestorLockHead internal lockHead;
    PropaneSecurityToken internal token;

    address internal issuer = makeAddr("issuer");
    address internal operator = makeAddr("operator");
    address internal ta = makeAddr("transferAgent");
    address internal keeper = makeAddr("recordKeeper");
    address internal treasury = makeAddr("issuerTreasury");

    uint8 internal constant US = PropaneRegions.REGION_US;
    uint8 internal constant EU = PropaneRegions.REGION_EU;
    uint8 internal constant JP = PropaneRegions.REGION_JP;
    uint8 internal constant OTHER = PropaneRegions.REGION_OTHER;
    uint8 internal constant FORBIDDEN = PropaneRegions.REGION_FORBIDDEN;

    struct Truth {
        uint8 region;
        uint8 euCountry;
        bool accredited;
        bool qualified;
    }

    mapping(address => Truth) internal truth;
    address[] internal known;

    function setUp() public virtual override {
        super.setUp();
        _deploy(_config());
    }

    /// @dev Default: every optional rule disabled, flowback window closed. Tests override.
    function _config() internal view virtual returns (PropaneComplianceEngine.Config memory c) {
        c.periods.blockFlowbackEndTime = uint64(block.timestamp); // flowback window already over
    }

    function _proxy(address impl, bytes memory init) internal returns (address) {
        return address(new ERC1967Proxy(impl, init));
    }

    function _deploy(PropaneComplianceEngine.Config memory cfg) internal {
        maintainer = PropaneMaintainerService(
            _proxy(address(new PropaneMaintainerService()), abi.encodeWithSignature("initialize()"))
        );
        loc = PropaneInstitutional(
            _proxy(
                address(new PropaneInstitutional()),
                abi.encodeCall(PropaneInstitutional.initialize, (address(maintainer)))
            )
        );
        maintainer.addUniversalRole(issuer, PropaneRoles.ROLE_OWNER);
        maintainer.addUniversalRole(operator, PropaneRoles.ROLE_PROPANE);
        maintainer.addUniversalRole(ta, PropaneRoles.ROLE_OFFICER);

        registry = PropaneComplianceRegistry(
            _proxy(
                address(new PropaneComplianceRegistry()),
                abi.encodeCall(PropaneComplianceRegistry.initialize, (address(loc)))
            )
        );
        engine = PropaneComplianceEngine(
            _proxy(
                address(new PropaneComplianceEngine()),
                abi.encodeCall(PropaneComplianceEngine.initialize, (address(loc), cfg))
            )
        );
        census = PropaneCensus(
            _proxy(address(new PropaneCensus()), abi.encodeCall(PropaneCensus.initialize, (address(loc))))
        );
        lockHead = PropaneInvestorLockHead(
            _proxy(
                address(new PropaneInvestorLockHead()),
                abi.encodeCall(PropaneInvestorLockHead.initialize, (address(loc)))
            )
        );
        token = PropaneSecurityToken(
            _proxy(
                address(new PropaneSecurityToken()),
                abi.encodeCall(PropaneSecurityToken.initialize, (address(loc), "Propane Fund", "PRF", 0))
            )
        );

        loc.setInstitutionalService(PropaneServices.SVC_REGISTRY, address(registry));
        loc.setInstitutionalService(PropaneServices.SVC_COMPLIANCE, address(engine));
        loc.setInstitutionalService(PropaneServices.SVC_CENSUS, address(census));
        loc.setInstitutionalService(PropaneServices.SVC_LOCK_HEAD, address(lockHead));
        loc.setInstitutionalService(PropaneServices.SVC_TOKEN, address(token));
        loc.setInstitutionalService(PropaneServices.SVC_RECORD_KEEPER, keeper);

        vm.prank(operator);
        engine.setPlatformWallet(treasury, true);
    }

    // ---------------------------------------------------------------- actions

    function _register(address w, uint8 region, uint8 euCountry, bool acc, bool qual) internal {
        _register(w, region, euCountry, acc, qual, false);
    }

    function _register(address w, uint8 region, uint8 euCountry, bool acc, bool qual, bool liq) internal {
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(region, euCountry, acc, qual, liq);
        vm.prank(ta);
        registry.registerWallet(w, i, proof);
        truth[w] = Truth(region, euCountry, acc, qual);
        known.push(w);
    }

    function _update(address w, uint8 region, uint8 euCountry, bool acc, bool qual) internal {
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(region, euCountry, acc, qual, false);
        vm.prank(ta);
        registry.updateAttributes(w, i, proof);
        truth[w] = Truth(region, euCountry, acc, qual);
    }

    function _attrInput(uint8 region, uint8 euCountry, bool acc, bool qual, bool liq)
        internal
        returns (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof)
    {
        uint256[] memory v = new uint256[](5);
        FheType[] memory t = new FheType[](5);
        (v[0], t[0]) = (region, FheType.Uint8);
        (v[1], t[1]) = (euCountry, FheType.Uint8);
        (v[2], t[2]) = (acc ? 1 : 0, FheType.Bool);
        (v[3], t[3]) = (qual ? 1 : 0, FheType.Bool);
        (v[4], t[4]) = (liq ? 1 : 0, FheType.Bool);
        bytes32[] memory h;
        (h, proof) = encrypt(v, t, ta, address(registry));
        i = IPropaneComplianceRegistry.EncryptedAttributesInput({
            region: externalEuint8.wrap(h[0]),
            euCountry: externalEuint8.wrap(h[1]),
            accredited: externalEbool.wrap(h[2]),
            qualified: externalEbool.wrap(h[3]),
            liquidateOnly: externalEbool.wrap(h[4])
        });
    }

    function _issue(address to, uint64 amount) internal returns (uint64) {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, issuer, address(token));
        vm.prank(issuer);
        return decrypt(token.issue(to, h, p));
    }

    function _transfer(address from, address to, uint64 amount) internal returns (uint64) {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, from, address(token));
        vm.prank(from);
        return decrypt(token.confidentialTransfer(to, h, p));
    }

    function _forced(address from, address to, uint64 amount) internal returns (uint64) {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, ta, address(token));
        vm.prank(ta);
        return decrypt(token.forcedTransfer(from, to, h, p));
    }

    function _burn(address from, uint64 amount) internal returns (uint64) {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, ta, address(token));
        vm.prank(ta);
        return decrypt(token.burn(from, h, p));
    }

    function _freeze(address w, uint64 amount) internal {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(amount, ta, address(token));
        vm.prank(ta);
        token.setFrozenTokens(w, h, p);
    }

    /// @dev One state-changing call per block, as on a live chain; the fhEVM meters HCU per block.
    function _nextBlock() internal {
        vm.roll(block.number + 1);
    }

    // ---------------------------------------------------------------- reads

    function _bal(address w) internal returns (uint64) {
        euint64 b = token.confidentialBalanceOf(w);
        return euint64.unwrap(b) == bytes32(0) ? 0 : decrypt(b);
    }

    function _code(address w) internal returns (uint8) {
        return decrypt(engine.lastCode(w));
    }

    function _counters() internal returns (uint32[9] memory r) {
        IPropaneCensus.Counters memory c = census.counters();
        r[0] = decrypt(c.total);
        r[1] = decrypt(c.accredited);
        r[2] = decrypt(c.us);
        r[3] = decrypt(c.usAccredited);
        r[4] = decrypt(c.jp);
        for (uint256 k = 0; k < 4; k++) {
            r[5 + k] = decrypt(c.euRetail[k]);
        }
    }

    /// @dev Census recomputed in the clear from decrypted balances and the test's own record of
    ///      attributes. Platform wallets excluded, as in the contracts.
    function _expectedCounters() internal returns (uint32[9] memory r) {
        uint8 slots = engine.euCountrySlots();
        for (uint256 i = 0; i < known.length; i++) {
            address w = known[i];
            if (engine.isPlatformWallet(w) || _bal(w) == 0) continue;
            Truth memory t = truth[w];
            r[0]++;
            if (t.accredited) r[1]++;
            if (t.region == US) r[2]++;
            if (t.region == US && t.accredited) r[3]++;
            if (t.region == JP) r[4]++;
            if (t.region == EU && !t.qualified && t.euCountry < slots) r[5 + t.euCountry]++;
        }
    }

    function _assertCensus() internal {
        uint32[9] memory got = _counters();
        uint32[9] memory want = _expectedCounters();
        for (uint256 k = 0; k < 9; k++) {
            assertEq(got[k], want[k], string.concat("census counter ", vm.toString(k)));
        }
    }

    function _allowed(bytes32 handle, address who) internal view returns (bool) {
        return _acl.isAllowed(handle, who);
    }
}
