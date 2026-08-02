# Bucket 0 — Foundational decisions

Decisions recorded here are the ones every later bucket inherits and that cannot
be revised without rewriting what is downstream. Each is stated with the
alternative that was rejected and the evidence that decided it. Evidence
references are to the reference implementations under
`/mnt/adiii_dev/Ethereum-dev/propane-privacy-local/reference/`.

Status: **closed**, 2 August 2026.

---

## D1 — Storage layout: ERC-7201 namespaced storage

Namespace identifiers take the form `propane.storage.<ContractName>`, annotated
`@custom:storage-location erc7201:<id>`, with the location precomputed as a
`private constant`:

```
erc7201(id) = keccak256(keccak256(id) - 1) & ~0xff
```

**Rejected:** inherited data stores with reserved `__gap` arrays, as used by the
DS Protocol.

**Why:** the reference broke its own convention. `ServiceConsumerDataStore`
follows a documented 50-slot rule (1 slot + `__gap[49]`), but
`BlackListManagerDataStore.sol:45` reserves `__gap[45]` for 3 used slots — 48
accounted, not 50 — because an `EnumerableSet` occupies two slots and the count
was done by hand. Namespaced storage removes the counting.

**Consequence:** `forge inspect <C> storage-layout` returns an empty layout for
namespaced contracts, so a committed storage-layout golden file is not a usable
regression guard. The equivalent guards are the namespace-slot assertions in
`test/Bucket0.t.sol` plus, once real structs exist, a field-offset test. Solc
will not catch a field reordered inside a namespace struct.

---

## D2 — Upgradeability and contract decomposition: UUPS with modular rules

UUPS proxies. Rule logic is decomposed into small independent module contracts
behind a coordinator. **No Diamond, and no linked libraries.**

**Rejected:**

- *UUPS + linked libraries* — the DS Protocol approach.
- *EIP-2535 Diamond* — solves size structurally, but costs facet-cut and
  selector-clash management, less turnkey tooling, and uneven auditor
  familiarity, which is a real cost for a regulated asset.

**Why:** the size wall is demonstrated, not hypothetical. The reference compiles
at solc 0.8.22, optimizer on, `runs = 200`, no `viaIR`, and still had to evict
two libraries to stay under EIP-170's 24,576 bytes: `TokenLibrary` and
`ComplianceServiceLibrary` (`ComplianceServiceRegulated.sol:30-568`, ~538
lines). The mass is two functions — `completeTransferCheck` (file lines 231-434,
~204 lines) and `preIssuanceCheck` (435-560, ~126 lines).

The eviction had a cascading cost. A library cannot inherit the service locator,
so every dependency is injected as an `address[] _services` array rebuilt on each
call (`ComplianceServiceRegulated.sol:923-931`). That injection is the direct
cause of the codebase's worst defect: inside the library `DS_TOKEN = 0` and
`REGISTRY_SERVICE = 1` are array indices, while in `IDSServiceConsumer.sol` the
same identifiers are service IDs `2` and `4`. Both meanings appear within a few
lines of the same expression.

Decomposition avoids building a 204-line `completeTransferCheck` at all. This is
the one axis on which the ERC-3643 side is ahead: Tokeny's T-REX implements the
same rule surface as thirteen independent modules under
`trex/contracts/compliance/modular/modules/`. Two independent teams hit the same
wall; one answered with libraries, the other with modules.

**Consequence:** module boundaries are a first-class design concern from Bucket 5
onward, and this converges with Bucket 7's pluggable-jurisdiction goal — a
regime is a module.

---

## D3 — Error channels

Custom errors for administrative reverts. A catalogued numeric code space for
compliance outcomes, with a single source of truth shared by the view path and
the revert path.

**Why:** the non-mutating `pre*Check` returning `(uint256 code, string reason)`
instead of reverting is what makes the asset composable, and is what integrators
consume. Custom errors cannot carry it. The reference keeps the two paths
consistent by hand and fails: `preIssuanceCheck` omits the authorised-securities
cap, so a client can be told an issuance is valid and still revert.

---

## D4 — One identifier, one meaning

No identifier may carry different values in different namespaces. Shared
constants live in a single library. Enforced by a build-failing CI step in
`.github/workflows/contracts.yml`.

**Why:** see D2. The constant shadowing produced by the library split is the most
error-prone feature of the reference codebase.

---

## D5 — Compiler and toolchain pins

| Setting | Value | Rationale |
|---|---|---|
| `solc_version` | `0.8.28` | settled release; supports up to `prague` |
| `evm_version` | `cancun` | mainnet target; safe by construction |
| `optimizer` | on, `runs = 10000` | see below |
| `via_ir` | `false` | not needed for size under D2; keeps builds fast |
| licence | MIT | matches repository `LICENSE` |

**Deploy target: Ethereum mainnet.** Mainnet activated Fusaka in December 2025
(Pectra, May 2025). Pinning `cancun` is therefore deploy-safe by construction,
since a pin at or below the live fork always is. `cancun` is also solc 0.8.28's
own default and the newest level whose opcodes this codebase actually uses —
`TSTORE`/`TLOAD` for reentrancy guards and `MCOPY`. Neither `prague` nor `osaka`
adds anything at the codegen level here.

**Trap worth recording:** forge silently downgrades an `evm_version` the pinned
solc cannot support and still reports a successful build. Requesting `osaka`
under solc 0.8.28 compiles as `prague` with no warning. The authoritative check
is `forge build --build-info` and reading `settings.evmVersion` back.

**`optimizer_runs = 10000`** departs from the reference's `200`. Under D2 no
contract approaches EIP-170, so the size/runtime trade can be spent on runtime
gas rather than bytecode. The rule ladder executes on every transfer and this
deploys to mainnet, where runtime gas is the scarce resource.
`forge build --sizes` in CI is the guard if a module ever grows.

---

## D6 — Dependency management

Soldeer, with `dependencies/` gitignored and `foundry.toml` plus `soldeer.lock`
committed as the source of truth. Restore with
`forge soldeer install --config-location foundry`.

Security-relevant dependencies are pinned **by git URL and tag against the
upstream repository**, not the Soldeer registry:

```toml
"@openzeppelin-contracts"             = { version = "5.7.0", git = "...", tag = "v5.7.0" }
"@openzeppelin-contracts-upgradeable" = { version = "5.7.0", git = "...", tag = "v5.7.0" }
```

**Why:** registry packages for OpenZeppelin are third-party mirrors, not
first-party publishes. The registry entry for
`@openzeppelin-contracts-upgradeable` records `github_url` as
`OpenZeppelin/openzeppelin-upgrades` — the upgrade *plugin* repository, not the
contracts library. The mirror is well maintained (5.7.0 appeared roughly three
hours after upstream), but provenance from the vendor's own repository is a
question an auditor can reasonably ask. This mirrors the configuration used by
`OriginProtocol/origin-dollar`.

`remappings_generate = false`: Soldeer otherwise rewrites `remappings.txt` on
every install with version-suffixed paths that do not match the
`@openzeppelin/contracts/...` prefix the upgradeable library uses for its own
imports. Remappings are declared explicitly in `foundry.toml`.

**Note:** `forge soldeer install` requires `--config-location foundry` in
non-interactive contexts; without a TTY it fails with a misleading
`error during IO operation: not connected`.

---

## Open, deferred by decision

- **Field-offset regression test** for namespace structs. Deferred to Bucket 1,
  when the first real struct exists; testing it against a one-field probe proves
  nothing.
- **Licence** is MIT and matches the repository. BUSL-1.1 was considered and
  rejected for now; revisit before first public deployment.
