# Vendored licence texts — provenance

`tools/licenses/acknowledgements.py` (spec §11 PUB-10) writes every build's
`Contents/Resources/Acknowledgements.txt`. One text it needs is not in any lockfile or
package, so it is vendored here, as `.txt`, never `.md`: `tools/proof/gate.py` counts no
`*.md` under `tools/licenses/` as an input of the `app` step. Slaude's texts are read from the
assistant helper's resolved SwiftPM checkout, and Sparkle's from its resolved package, at build
time (spec §11 SA-10); neither is vendored.

| File | What | Source | SHA-256 | Fetched |
|---|---|---|---|---|
| `spdx/MIT.txt` | The SPDX MIT text with its `Copyright (c) <year> <copyright holders>` line and the blank line after it removed; the generator writes a package's declared authors above it | <https://raw.githubusercontent.com/spdx/license-list-data/f715b3660bb164c3d0b81cba9ce94e3c558c4048/text/MIT.txt>, `spdx/license-list-data` commit `f715b3660bb164c3d0b81cba9ce94e3c558c4048` (the upstream file's SHA-256 `b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5`) | `9645fb6e878aebd5e959be648a71973a108d4aa0d18eee478d0579066ad99958` | 2026-10-28 |

`spdx/<id>.txt` is the canonical text of one SPDX id, used for a package that ships no
licence file of its own. Only MIT is needed today (`rquickjs-core`, `rquickjs-sys`); a
package declaring an id with no file here fails the build, naming the package and the id, and
the fix is to vendor that id's text the same way.
