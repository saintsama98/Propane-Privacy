# Propane-Privacy

Institutional compliance layer for RWAs and multi strategy funds.

> This project was developed privately and published once it had been tested against its original design. Its full development history is published on a single `main` branch so reviewers can follow it in one place.

A permissioned security token can encrypt its balances and still publish its holder base. The rules that make an asset a regulated one are not only about who may hold it. They also count the holders: no more than so many investors in total, per jurisdiction, per category, and never fewer than a minimum. Those rules need the whole holder base to evaluate, so existing confidential token designs either leave them out or keep the census in the clear.

Propane enforces the full permissioned-token rulebook, including the investor census, over encrypted state. Balances, transfer amounts, investor attributes and the investor counts are all encrypted with fully homomorphic encryption (Zama fhEVM). The chain learns that a transfer happened and that the issuer's rules were satisfied. It does not learn who holds what, which rule refused a transfer, or how close any category is to its cap.

The token holds balances and no rules. Every decision is delegated to a compliance service resolved at call time, so the compliance posture of an asset is a deployment choice rather than a property of the token.

## What this build establishes

1. **The census rules run on encrypted counters.** Total, accredited, US, US accredited, JP and EU retail per country are kept as encrypted counters that are never decrypted publicly. Caps are evaluated jointly over both parties and the counters, including the slot that is freed when a sender leaves the same category in the same transfer, and the US cap expressed as a percentage of all investors.
2. **The counters are exact.** A randomized test drives arbitrary sequences of transfers, self transfers, issuances, burns, forced transfers and attribute changes, and checks after every operation that each encrypted counter equals the count recomputed in the clear. The on-chain recomputation then reproduces the live census exactly.
3. **It fits the host limits.** The worst case measured, a transfer under the full rulebook with four rule heads and two open lock records, costs 13.06M HCU against the per-transaction limit of 20M and stays within the 5M sequential depth limit.

## Architecture

Every service is a UUPS proxy with ERC-7201 namespaced storage. Services hold one reference, to the locator, and resolve each other by identifier at call time.

| Layer | Contracts | Role |
|---|---|---|
| Authority | `PropaneMaintainerService` | Ranked trust roles. Root of every authorization check and upgrade. |
| Locator | `PropaneInstitutional` | Service identifier to address. Replacing one entry replaces one service. |
| Registry | `PropaneComplianceRegistry` | Whether a wallet is registered (public) and its attested attributes (encrypted). No personal data, hashed or otherwise. |
| Engine | `PropaneComplianceEngine` | The rule ladder over encrypted balances, amounts and attributes. Returns the amount that may move: the requested amount or zero. |
| Census | `PropaneCensus` | The encrypted investor counters, the census rules, and recomputation from chain state. |
| Heads | `PropaneInvestorLockHead`, `...BlacklistHead`, `...TempBarredHead`, `...WhitelistHead`, `...EOAHead` | Independent rule modules: issuance hold-up, encrypted deny list, encrypted time bar, offering admission, account shape. |
| Asset | `PropaneSecurityToken` | Encrypted balances, freeze, forced transfer, burn, pause. No rules of its own. |

### A transfer, in order

```
holder submits an encrypted amount to the token
  -> token computes available (balance minus frozen) and hands both to the engine
  -> engine reads balances and attributes, asks the heads and the lock head
  -> census evaluates the caps against its counters
  -> engine folds the ladder: effective = rules passed ? amount : 0
  -> census applies a delta, possibly zero, to every counter
  -> token moves the effective amount
```

Nothing in this path reverts on an encrypted condition. A refused transfer moves zero, so a refusal is not published.

## Design choices

**A refusal is not a revert.** A reverted transfer tells everyone that some rule failed. Here the transfer always succeeds and moves either the amount or nothing. The reason code is written for the sender and the record keeper only.

**Every counter moves on every operation.** If a counter changed only when a holder entered or left, differencing it across blocks would reveal each entry and exit and its category. Every transfer, issuance, burn, forced transfer and attribute change rewrites every counter, with a delta that may be zero.

**The pre-check is not an oracle.** A view that anyone can call about anyone is a way to read investor attributes without transacting. `requestTransferCheck` answers only the investor, a venue the investor has delegated to, or the transfer agent. The venue receives the verdict; only the investor receives the reason.

**The census repairs itself from chain state.** Counters are never overwritten by an administrator. `beginRecompute`, `continueRecompute` and `finishRecompute` rebuild them in batches from balances and attributes, so the result needs no trust in whoever triggers it.

**Configuration is public, and slow.** Caps, minimums and lock periods describe the offering, not any investor, so they are readable. A change takes effect after a one-day delay, so a cap cannot be lowered and observed within a single window to probe the census.

**Enforcement survives confidentiality.** The transfer agent can freeze, force-transfer, seize into an issuer wallet and burn. These paths skip eligibility by design and still pass through the census, so the counters stay correct.

## Roles

| Role | Can do |
|---|---|
| Super owner | Upgrades, the roles entry in the locator, every role grant |
| Owner (issuer) | Issue, schedule rulebook changes, set offering admission, pause |
| Propane (operator) | Wire services in the locator, mark platform wallets |
| Officer (transfer agent) | Register wallets and write attributes, issue, burn, freeze, force-transfer, deny-list and bar investors, recompute the census |
| Record keeper | Not a caller. The key granted decryption of every handle the system creates: balances, attributes, counters, reason codes |
| Investor | Transfer, pre-check its own transfers, delegate pre-checks to a venue |

A role other than super owner can only grant or remove its own role.

## Build and test

Foundry, solc 0.8.28, EVM `cancun`. Dependencies are installed with Soldeer.

```shell
cd contracts
forge soldeer install --config-location foundry
forge build --sizes
forge test
```

Tests run in isolate mode, one transaction per call, against the real fhEVM host contracts deployed in Foundry by [forge-fhevm](https://github.com/zama-ai/forge-fhevm). That is the only mode in which per-transaction HCU and transient access grants behave as they do on chain.

| Suite | Covers |
|---|---|
| `test/scenario/CoreFlows.t.sol` | Issue, transfer, refusals, freeze, forced transfer, seizure, burn, attribute changes, sender exit |
| `test/scenario/Rules.t.sol` | Each rule family, with the census exemptions exercised explicitly |
| `test/scenario/Privacy.t.sol` | Who may decrypt which handle; pre-check scoping; engine, census and token guards |
| `test/scenario/CensusSequence.t.sol` | The census invariant under random sequences, and recomputation |
| `test/scenario/Heads.t.sol`, `Upgrades.t.sol` | Rule heads; upgrade authority, state preservation, compliance swap |
| `test/measure/` | HCU per operation, and the worst case under the unmodified host limits |
| `test/unit/`, `test/invariant/`, `test/formal/` | Role scoping (unit, stateful invariant, Halmos), storage namespace slots, an fhEVM smoke test |

## Status

**Research and development ongoing.** Nothing here is complete, audited or
intended for production use. Interfaces, storage layouts and the contents of this
repository are expected to change without notice.

## License

BUSL-1.1. See [`LICENSE`](LICENSE).
