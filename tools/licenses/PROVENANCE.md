# Vendored licence texts — provenance

`tools/licenses/acknowledgements.py` (spec §11 PUB-10) writes every build's
`Contents/Resources/Acknowledgements.txt`. Two texts it needs are not in any lockfile or
package, so they are vendored here. Both are `.txt`, never `.md`: `tools/proof/gate.py`
counts no `*.md` under `tools/licenses/` as an input of the `app` step.

| File | What | Source | SHA-256 | Fetched |
|---|---|---|---|---|
| `bun/LICENSE.txt` | Bun's `LICENSE.md`, verbatim (no trailing newline, as published) | <https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.6/LICENSE.md>, tag `bun-v1.3.6` | `4cf82fd717b2b34dfabf6087c35fcffd28386054f1791d2e6ecfdfcafe0131a8` | 2026-10-28 |
| `spdx/MIT.txt` | The SPDX MIT text with its `Copyright (c) <year> <copyright holders>` line and the blank line after it removed; the generator writes a package's declared authors above it | <https://raw.githubusercontent.com/spdx/license-list-data/f715b3660bb164c3d0b81cba9ce94e3c558c4048/text/MIT.txt>, `spdx/license-list-data` commit `f715b3660bb164c3d0b81cba9ce94e3c558c4048` (the upstream file's SHA-256 `b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5`) | `9645fb6e878aebd5e959be648a71973a108d4aa0d18eee478d0579066ad99958` | 2026-10-28 |

`spdx/<id>.txt` is the canonical text of one SPDX id, used for a package that ships no
licence file of its own. Only MIT is needed today (`rquickjs-core`, `rquickjs-sys`,
`standardwebhooks`); a package declaring an id with no file here fails the build, naming
the package and the id, and the fix is to vendor that id's text the same way.

## Re-vendoring Bun's licence

`BUN_LICENSE_VERSION` in `acknowledgements.py` is the Bun this text came from. The publish
workflow installs exactly that Bun (`oven-sh/setup-bun`'s `bun-version`, read with
`acknowledgements.py --print-bun-version`, spec §11 PUB-12), and a Distribution build whose
`bun --version` differs fails (`--strict-bun`); Debug and Release write a note instead. After
upgrading Bun:

```sh
V="$(bun --version)"
curl -fsSL -o tools/licenses/bun/LICENSE.txt \
  "https://raw.githubusercontent.com/oven-sh/bun/bun-v$V/LICENSE.md"
shasum -a 256 tools/licenses/bun/LICENSE.txt
```

then set `BUN_LICENSE_VERSION` to `$V`, and update the row above (tag, SHA-256, date).
