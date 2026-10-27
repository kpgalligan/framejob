# The bundled encoders — provenance

Road map "codec-export" C0, spec §11 CX-2..CX-5. `tools/codecs/build_codecs.py` holds these
pins (`PINS`) and is the only thing that fetches or builds them. It installs each library's
archive, its headers and the licence texts below into `build/codecs/`, and the app bundle
gets the texts in `Contents/Resources/Licenses/<library>/` (project.yml's "Copy Codec
Licences"; `tools/proof/dist_check.py` D40/D41). No library source is in git.

Fetched and recorded 2026-10-27. The commit is `git get-tar-commit-id` read from the
downloaded tarball (gunzipped), and it equals the commit the spike built from (a shallow
clone of the same tag, `designs/codec-export.md` §S). The SHA-256 is the downloaded
`.tar.gz`'s.

## SVT-AV1 v4.2.0

- URL: <https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.gz>
  (11,070,537 bytes)
- Tag: `v4.2.0`; commit `9292ec8e32bce26f781f277ec8739b53426c4300`
- SHA-256: `c7b13c4a84bd3751aa35fcc72be13e6875467e7c2216879251a486e5b1e4e740`
- Configure (under `build_env()`: `MACOSX_DEPLOYMENT_TARGET=26.0`, PATH
  `/usr/bin:/bin:/usr/sbin:/sbin` plus cmake's folder):

  ```
  cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_INSTALL_PREFIX=<stage>
        -DBUILD_SHARED_LIBS=OFF -DBUILD_DEC=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
  cmake --build <build> -j<ncpu> && cmake --install <build>
  ```
- Output: `lib/libSvtAv1Enc.a`, `include/svt-av1/*.h`.
- Licence: BSD 3-Clause Clear (`LICENSE.md`), which grants no patent rights; parts are
  under AOM's BSD 2-Clause (`LICENSE-BSD2.md`).
- Patent grant: the Alliance for Open Media Patent License 1.0 (`PATENTS.md`):
  royalty-free; a binary distribution reproduces the licence in its documentation or
  legal notices; it terminates for a party that sues over AV1 patents.
- Shipped texts (`Contents/Resources/Licenses/svt-av1/`): `LICENSE.md`, `LICENSE-BSD2.md`,
  `PATENTS.md`, `fastfeat-LICENSE` (`third_party/fastfeat/LICENSE`),
  `safestringlib-LICENSE` (`third_party/safestringlib/LICENSE`).
- Third-party code in `libSvtAv1Enc.a` (read with `ar t` on this build, 235 members):
  - fastfeat, BSD (Edward Rosten): `fast.c.o`, `fast_9.c.o`;
  - `vector.c.o` (`Source/Lib/Codec/vector.c`), MIT, Copyright (c) 2016 Peter
    Goldsborough: its notice is only in the source file's header, not in a LICENSE file,
    so it is not among the shipped texts — the acknowledgements (#376) must reproduce it;
  - `aom_dsp`'s and `aom_convolve8`'s members, AOM's BSD 2-Clause with the AOM patent
    licence (the texts above);
  - safestringlib is NOT in this archive: SVT's CMakeLists compiles it only where the
    platform lacks `strcpy_s`/`strncpy_s`/`strnlen_s`, and no `*_s.c.o` or
    `safe_str_constraint.c.o` member is present. Its licence ships anyway, as pinned.

## libvpx v1.17.0

- URL: <https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz>
  (5,670,546 bytes)
- Tag: `v1.17.0`; commit `6df3ec34557879fff673706f4a1d9fbd0f3a6f0e`
- SHA-256: `1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a`
- Configure (the same `build_env()`; the `arm64-darwin25-gcc` target adds only
  `-arch arm64`, so the deployment target comes from the environment):

  ```
  configure --target=arm64-darwin25-gcc --prefix=<stage> --enable-static --disable-shared
            --disable-vp8 --enable-vp9 --enable-vp9-highbitdepth --disable-vp9-decoder
            --disable-examples --disable-tools --disable-unit-tests --disable-docs
            --disable-webm-io --disable-libyuv
  make -j<ncpu> && make install
  ```
- Output: `lib/libvpx.a`, `include/vpx/*.h`.
- Licence: BSD 3-Clause (the WebM Project authors, `LICENSE`; `AUTHORS` names them).
- Patent grant: Google's "Additional IP Rights Grant (Patents)" (`PATENTS`): royalty-free,
  terminates for a party that sues over the WebM codecs' patents.
- Shipped texts (`Contents/Resources/Licenses/libvpx/`): `LICENSE`, `PATENTS`, `AUTHORS`.
- Third-party code in `libvpx.a`: none (178 members, `ar t`; libyuv and libwebm are
  disabled and were only ever vpxenc's).

## Tools

cmake from Homebrew (`brew install cmake`; 4.1.0 here), found on PATH or in
`/opt/homebrew/bin` or `/usr/local/bin`; the system's `/usr/bin/perl` (libvpx's rtcd
generator); Xcode's clang through `xcrun`. No nasm, yasm, meson or ninja: on arm64 both
libraries' SIMD is Neon C intrinsics.

## Risk

GitLab and GitHub generate these archives on request. If either host ever regenerates a
tag's archive with different bytes, the digest check fails the build naming both digests
(CX-5 (3)); the fix is to compare the new tarball's `git get-tar-commit-id` and contents
with the pin's, then re-pin, never to drop the check.
