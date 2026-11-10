# CLAUDE.md

shopbits: building blocks for shopping systems, written in Nim (>= 2.0, developed
on 2.4.0). MIT licensed, experimental and educational. **This is a public
repository.**

## Commands

    nimble test                          # compile and run every tests/t*.nim (unittest)
    nim c -r tests/tstructured_code.nim  # a single test file
    nim check src/shopbits.nim           # type-check without running anything
    nimble check                         # validates the .nimble file only; it does not compile
    nim c -r tools/shopbits_check.nim examples/data   # check a data directory

Compiled test binaries land in `tests/` and are git-ignored.

## Layout

- `src/shopbits.nim`: money, prices, taxes (early, experimental)
- `src/shopbits/pm_decimals.nim`: fixed-precision decimals on int64; restricted set
  of operations, not production grade
- `src/shopbits/tax_nexus.nim`: tax nexus = seller + delivery source; selects a set of
  tax rules (tax, destination, goods type, business type -> rate, treatment). A sale can
  have several taxes: one `TaxLine` per tax with a matching rule (first match wins per
  tax). A sale that is not allowed is a returned outcome (`TaxLookup`, `TaxedLineItem`),
  not an exception. `applyTax` turns the `CatalogPrice` of a `LineItem` (no tax
  information) into an `OrderPrice` (with tax lines, and gross, net and tax amounts)
  using its nexus. All taxes are computed on the same net amount; each line is rounded
  and the total tax is the sum of the lines, so net + tax == gross exactly
- `src/shopbits/date.nim`: calendar `Date` (no time, no zone) for effective dates
- `src/shopbits/snapshot.nim`: loads and validates reference data (nexuses) from a
  directory of JSON files into an immutable `Snapshot` whose `id` is the SHA-256 of the
  files' contents (`sha256.nim`). Strict: unknown fields and files are errors, and all
  problems are collected with file and position. The format is documented at the top of
  the module
- `src/shopbits/structured_code.nim` and `structured_code/`: generic library for
  fixed-width codes made of named slots (SKUs and similar)
  - `layout.nim`: `Layout`, validation, prefix handling
  - `query.nim`: typed query algebra (`or`, `and`, `-`, `not`, `<=`, `in`)
  - `define.nim`: `defineStructuredCode` macro (code type, accessors, queries)
  - `family.nim`: `defineCodeFamily` macro (several kinds of codes in one family)
- `tools/`: command line tools (not part of the package); `examples/data`: a small
  fictional data set
- `tests/`: one `t<module>.nim` per module; `tests/config.nims` puts `src` on the path

## Rules for this repo

- Keep everything domain-neutral. No employer-, customer- or product-specific names,
  identifiers, example data or internal documents, in code, docs, tests or commit
  messages. Use neutral examples (e.g. a SKU of category, color and size).
- Do not push unless asked. Do not change the git user config.
- Do not commit `claude.txt`, `nimcache/` or compiled test binaries.
- Example and test data must be fictional (made-up sellers, rates and rule changes). Real
  reference data, especially commercial data, belongs in a separate private repository.

## Nim conventions and gotchas

- 2-space indent; `##` doc comments on every exported symbol; `func` for pure code,
  `proc` otherwise (code that reads module-level `let`s cannot be a `func`).
- Identifiers ignore case and underscores after the first character, and cannot start
  or end with `_`.
- Query operators are `or`, `and`, `-`, `not`, never `|`/`&` (in Nim `&` binds weaker
  than `|`). Comparisons (`<=`, `in`, `==`) bind tighter than `and`/`or`, so
  parenthesize a query that is an operand: `x <= (a or b)`.
- Each kind of code is its own `distinct string` type. Keep it that way: wrong slots and
  mixed kinds must fail at compile time, and tests assert that with
  `check not compiles(...)`.
- The macros in `define.nim` and `family.nim` generate source text for `parseStmt`.
  The generated code is resolved at the call site, so callers need `std/hashes` and
  `std/options` (`structured_code` re-exports them). Compile a real use after
  changing them: errors point into generated code.
- Generic procs that need a type's layout use the per-type `layoutOf` hook with
  `mixin layoutOf`.
- `<=` on queries is decided exactly (`isEmpty` in `query.nim`). A randomized test
  compares it with brute-force set algebra; keep it passing when touching the algebra.

## Reference data

- Tax lookups take the day they are for (`asOf`), with no default: a result must never
  silently depend on today's date. Both ends of a rule's period are inclusive.
- Rates are strings in files, never JSON numbers (no floats).
- Changing the file format means changing `SchemaVersion`, the module docs, the example
  data and the loader tests together.

## Tests

- Every behavior change needs a test that asserts real behavior. No placeholder
  assertions (`or true`), and check that an adjusted test still tests what it was
  written for.
- Do not name helpers `check`, `test` or `suite` (they shadow unittest).
- Build expected strings with `repeat` instead of hand-counted `?` runs.
- Run `nimble test` before calling anything done, and report failures as they are.

## Docs

- Module docs (`##` at the top of each module) are the main documentation of
  `structured_code`. Update the README when modules are added or removed.
- Code examples in docs must compile; verify them before committing.
