# Propane-Privacy

institutional compliance layer for real world assets | Re: onchain tokenization &amp; privacy

## Overview

A service-oriented system: independently deployed, independently upgradeable
contracts that resolve one another through a service registry rather than
holding fixed references. Authority is rooted in a roles contract. A registry
holds what has been attested about an investor; a compliance layer reads that
record and returns a verdict; the asset carries no rules of its own.

Compliance runs as two paths over one rule set — an authoritative path that
enforces and records, and a non-mutating path that lets an integrating protocol
establish in advance whether an operation would succeed. The rule surface is
decomposed into independent modules rather than a single engine, so compliance
posture is a deployment choice and the core stays instrument-agnostic.

Ethereum mainnet. UUPS proxies, ERC-7201 namespaced storage.

## Status

**Research and development ongoing.** Nothing here is complete, audited or
intended for production use. Interfaces, storage layouts and the contents of this
repository are expected to change without notice.

## License

BUSL-1.1. See [`LICENSE`](LICENSE).
