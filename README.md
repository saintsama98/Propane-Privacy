# Propane-Privacy

institutional compliance layer for real world assets | Re: onchain tokenization &amp; privacy

## How this is built

The design is derived from a source-level reading of existing permissioned-token
implementations rather than from their documentation: where the prior art has
settled on something that works — a compliance check that is both enforced on
transfer and simulatable by third parties beforehand, identity-scoped rather than
address-scoped locks, ranked operator roles with genuine separation of duties —
it is reproduced closely, and where it carries defects those are recorded and
deliberately not reproduced. The contracts target Ethereum mainnet, use UUPS
proxies with ERC-7201 namespaced storage, and decompose the rule surface into
small independent modules rather than one large rule engine, so that no contract
approaches the EIP-170 size limit.

## Status

**Research and development ongoing.** Nothing here is complete, audited or
intended for production use. Interfaces, storage layouts and the contents of this
repository are expected to change without notice.
