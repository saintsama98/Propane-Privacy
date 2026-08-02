# Propane contracts

Foundry project.

**Research and development ongoing.** Not complete, not audited, not for production.

## Setup

Dependencies are managed with [Soldeer](https://soldeer.xyz) and vendored into
`dependencies/`, which is gitignored. `foundry.toml` and `soldeer.lock` are the
committed source of truth, so a fresh clone needs one restore step — and no
`git submodule` handling:

```shell
forge soldeer install --config-location foundry
```

The `--config-location foundry` flag is required in any non-interactive context;
without a TTY the command otherwise fails with a misleading
`error during IO operation: not connected`.

## Usage

```shell
forge build          # compile
forge test           # run the suite
forge fmt            # format
forge build --sizes  # EIP-170 budget check
```

## Conventions

Storage uses ERC-7201 namespaced layout, with namespace identifiers of the form
`propane.storage.<ContractName>` and the location precomputed as a `private
constant`. Note that `forge inspect <C> storage-layout` returns an empty layout
for such contracts; the namespace-slot assertions in `test/` are the regression
guard, and solc will not catch a field reordered inside a namespace struct.

Compiler settings are pinned deliberately and should not be changed casually.
Verify what solc actually received with `forge build --build-info` rather than
trusting `foundry.toml` — forge silently downgrades an `evm_version` the pinned
solc cannot support and still reports success.
