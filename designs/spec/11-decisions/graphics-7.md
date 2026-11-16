# Spec §11 — decisions: Graphics, the `.fjgraphic` package onward (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-46 on (G-46…G-49 when it was made), and a new G- decision is appended here.
It is new because `graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the
entries moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

- **G-46 — The Graphic dialog's Export… writes a `.fjgraphic` package:
  a stored zip of a manifest, the module, and only the project fonts and
  assets the engine saw it use; never a bundled font** (owner,
  2026-10-29; phase 2 of 2 of the graphic browser).
  (a) **The door.** Export… sits at the sheet's far left, with From
  File… to its right. It is enabled when a graphic is chosen and
  compiles. It opens an `NSSavePanel` as a sheet on the browser, named
  `<module>.fjgraphic`. The browser stays up; the result or the refusal
  goes in `graphicbrowser.message`. Exporting is no edit and no undo
  step.
  (b) **The usage rule.** A fresh library is built: the bundled faces,
  then the project's fonts, then its assets, and the module is compiled
  against it. Each frame is drawn (svg, then rasterize at the meta size,
  else the canvas) with default props: every frame up to 900, and past
  that 900 evenly spaced frames. Then the variants are drawn, one at a
  time with every other prop at its default: each `enum` option other
  than the default, and each boolean's opposite, in schema order, at most
  32, over 30 evenly spaced frames each. Every project font blob and asset
  the engine selected, measured, fell back to or resolved is packed; a
  bundled face never is. A frame that throws is skipped and counted.
  String and asset props are sampled only at their defaults. Accepted: a
  font or asset a module reaches only through a caller's own text or an
  asset prop's non-default value is not packed.
  (c) **The format.** A zip, stored (method 0), version needed 10,
  made-by `0x031E`, flag bit 11 (UTF-8 names), DOS time 0 and date
  `0x0021` (1980-01-01) so the bytes are deterministic, no extra fields,
  no directory entries, external attributes `0o100644 << 16`; no Zip64,
  so an archive over `u32::MAX` bytes is refused. `manifest.json` comes
  first, then `<module>.js`, then the fonts and assets, then the central
  directory. Its paths mirror `graphics/` (`fonts/<n>`, `assets/<n>`), so
  a later import is a copy. The manifest is pretty JSON with a trailing
  newline, in the key order `fjgraphic` (1), `module`, `title`,
  `category`, `description` (string or null), `app_version`, `files`
  (`path`, `name`, `size`, `sha256` each); `path` is the in-package path,
  `name` the file's name in its project folder, `sha256` lowercase hex;
  the manifest does not list itself. **A project font or asset whose name
  the package path cannot hold** (`\`, `:`, a control character, a
  leading `.`) **is never refused at export**: a legal in-package `<n>` is
  non-empty, at most 255 bytes, does not begin with `.`, and holds no
  `/`, `\`, `:` or control scalar (U+0000–U+001F, U+007F–U+009F). For
  `fonts/` and `assets/`, each on its own, the legal names are claimed
  first in the order given; then each illegal one, in order, has each run
  of `\`, `:` or control scalars made one `-` and its leading `.`s
  dropped (an empty result is `file`), and a name already claimed takes
  `-2`, `-3`, … before its last `.` (G-23 (c)'s form), the stem cut by
  whole scalars to stay within 255 bytes. `a:b.ttf` → `fonts/a-b.ttf`;
  `red\dot.png` → `assets/red-dot.png`; `a:b.ttf` beside a legal
  `a-b.ttf` → `fonts/a-b-2.ttf`. The manifest's `name` keeps the
  project's, so an import can restore it and `asset(name)` still
  resolves; a font is found by family, never by file name, so its renamed
  entry changes no picture. The core (`rc_graphic_package_write`) writes
  the archive and answers the manifest; Swift writes `.<file>.partial`
  beside the destination and moves it into place, replacing a file
  already there.
  (d) **The UTI** `com.kgalligan.framejob-graphic` ("Frame Job Graphic",
  conforming to `public.zip-archive` and `public.data`, extension
  `fjgraphic`) is exported only; the app does not open a `.fjgraphic`.
  (e) **`export_graphic {name, from, path}`** is the agent's mirror. It
  runs off main, like `render_graphic`, has no `scope`, and refuses
  `from` and an unknown name as `insert_graphic` does and a module that
  does not compile with (f) of G-45's sentence; a refusal writes nothing.
  It is ask-first in the assistant under AI-7's own criterion: it writes
  a file where the model chose.
  (f) **Import is not built.** It is filed as an issue when the phase
  closes.
  **Amended by G-47:** (d)'s UTI conforms to `public.data` and
  `public.content`, no longer to `public.zip-archive`, and the app opens a
  `.fjgraphic` as a Viewer; (f)'s import is built.

- **G-47 — Frame Job opens a `.fjgraphic`: the core checks the package,
  a sheet asks first, and the module, fonts and assets are copied into the
  front project's `graphics/` under the manifest's names** (owner,
  2026-10-29: "start with the extension for now"; #384). Amends G-46 (d)
  and (f).
  (a) **The doors.** The Finder door — a double-click, Open With, a drop
  on the Dock icon, a browser opening its download — reaches
  `ProjectDocumentController.openDocument(withContentsOf:…)`, which hands a
  URL whose extension is `fjgraphic` (any case) to the import and answers
  no document, no error; that open is not counted (#234), and nothing else
  it opens changes. The Graphic dialog's From File… takes a `.js` (inserted
  as before, G-45 (f)) or a `.fjgraphic` (imported). The agent's door is
  `import_graphic {path}`. File ▸ Open does not list the type, and there is
  no menu item.
  (b) **Where it goes.** The front project: the first window in
  `NSApp.orderedWindows` whose content is an `EditorViewController` with a
  `ProjectDocument`, else the first such window of an open project; with
  none, File ▸ New Project's untitled project, made for it. From File…
  imports into its own editor's project, and `import_graphic` into the
  project its call names. **The Finder door chooses only once launch and
  restoration are done**, so a package double-clicked while Frame Job is
  not running lands once, in one project: AppKit delivers a launch's
  open-documents event inside `finishLaunching`, after window restoration
  has begun, and restored projects are read concurrently
  (`canConcurrentlyReadDocuments`). The door therefore waits for the main
  queue's next turn — after `applicationDidFinishLaunching` — and then
  until `ProjectDocumentController` has no open or reopen in flight (a
  restored untitled project counted too), one more turn after the last
  ends, so AppKit has made the restored window. A restored project then
  takes the import; with none, the untitled project is made. AppKit asks
  `applicationShouldOpenUntitledFile` (the Welcome window) only for a
  launch with no document to open, so a launch whose open is a
  `.fjgraphic` shows no Welcome window and makes no second project; a
  Welcome window already up closes when the new project's window becomes
  main, as for any project.
  (c) **Checks.** The core's first (`rc_graphic_package_read`, below), then
  the app's: a regular file of 1 to `UInt32.max` bytes; each font's
  extension one of G-6's and the font loads in a throwaway library; each
  asset's extension one of G-23's set, its name `asset(name)` can use, and
  not empty. Every refusal is "<file name> cannot be imported: <the
  sentence>", and a refusal writes nothing. The core reads the archive's
  end record (within the last 22 + 65,535 bytes), one disk, the central
  directory in bounds; every entry stored (method 0), not encrypted, no data
  descriptor, both sizes equal, no Zip64 field, a UTF-8 name that is no
  directory and not repeated, its local header agreeing, its data in bounds
  and before the central directory, its CRC-32 right; `manifest.json`
  first, a JSON object whose `fjgraphic` is 1 (a larger whole number is
  "the package is format N; this Frame Job reads format 1 — a newer Frame
  Job wrote it"), whose `module` is a module name (G-3), whose `title`,
  `category` and `app_version` are strings and `description` a string or
  null, unknown keys ignored; `files` non-empty, each with a `path`, a
  `name`, a `size` and a lowercase-hex `sha256`, the first both `path` and
  `name` `<module>.js`, every other path `fonts/<n>` or `assets/<n>` with
  G-46 (c)'s legal `<n>`, every other `name` 1 to 247 bytes with no `/`,
  no control scalar and no leading `.`, no name twice in one folder; the
  entries after the manifest exactly the files' paths in order, each of
  the listed size and SHA-256, and the module UTF-8. It answers the
  manifest with each file's byte offset in the package.
  (d) **Names.** As the manifest names them: the module under `module`, a
  font or an asset under its `name` (so `Ver:dana.ttf` and `red\dot.png`,
  legalised in the package, come back as they were). A name already taken
  is decided per file. **The module:** a free name is written; a name
  whose file holds the same bytes is reused; otherwise the name (its root
  cut to 60 scalars) takes `-2`, `-3`, … until free. A name is free when
  the folder holds no such module and no clip draws it. **A font:** a free
  name is written, an identical file of exactly that name reused;
  otherwise `<stem>-2<.ext>`, `-3`, … (G-23 (c)'s form), reusing an
  identical file and writing at the first free name. A name that differs
  only in case is a different file. A font is found by family, never by
  file name, so a renamed font changes no picture. **An asset:** a free
  name is written, an identical file of exactly that name reused; any
  other file of that name refuses the import — "graphics/assets/<name>
  already holds a different picture, and this graphic reaches its own by
  asset("<name>"), so it cannot be renamed; rename or remove the project's
  file and import again" — because the module reaches it by name.
  (e) **Not an undo step and never dirty** (G-3): the import writes files.
  The fonts are written first, then the assets, then the module, none
  replacing a file; a failure removes every file this import wrote and is
  "graphics/<path> could not be written: <why>". One rescan follows. An
  untitled project carries the files at its first save (G-29 (g)).
  (f) **Ask first.** The Finder door and From File… show a sheet, Import
  Graphic: the title, the description, the module's name and what happens
  to it (written, already in this project, or written under another name
  because its own is taken), the fonts and the pictures each with
  "(already here)" or "(as <name>)", and "Importing copies these files
  into this project's graphics. It is not an Undo step." Import runs the
  plan again and imports; a refusal stays in the sheet. After Import the
  Graphic dialog opens on This Project with the module chosen and the
  sentence "Imported <title> as <module>. Added: … Already here: …." in its
  message line. A refusal before the sheet is an alert on the project's
  window, or an application-modal alert with no project.
  (g) **The UTI** `com.kgalligan.framejob-graphic` conforms to
  `public.data` and `public.content`, no longer to `public.zip-archive`,
  so a browser's "open safe files" does not unpack it and the Finder does
  not offer Archive Utility as its opener; it stays exported.
  (h) **Rank.** The app's `CFBundleDocumentTypes` gains a row, "Frame Job
  Graphic", role Viewer, no `NSDocumentClass` (the routing above is the
  only reader), ranked by V-5's `RC_PROJECT_HANDLER_RANK`: Alternate in
  Debug, so a Debug build never takes the type from the installed app,
  Owner in Release and Distribution. Release shares Distribution's bundle
  id, so to Launch Services they are one app.
  (i) **`import_graphic {path}`** answers `{name, renamed_from (only when
  it differs), title, module: written | reused, fonts: [{name,
  renamed_from?, action}], assets: [{name, action}], note}`. It runs on
  main, has no `scope`, and is not ask-first in the assistant: it writes
  only inside the project's `graphics/`, as `import_graphic_font` does.
  **Accepted:** two font files of one family in a project draw with
  whichever the engine picks; a module that does not compile is still
  imported, and the Graphic dialog lists it with its error.
- **G-48 — An inspector's one-line string field takes the row's width;
  amends G-34 (l)'s O1 and O8** (the owner, 2026-10-30). A module's
  `string` prop without `multiline`, and the Document tab's marker name,
  are an `InspectorNameField` that stretches to the row's trailing edge at
  any inspector width, where it was capped at 170 pt (≤ 170 required,
  == 170 at 249). `inspectorRow` owns the rule for every such field: it
  hugs at 1, the row gets no trailing spacer (a slider's and the Content
  area's reason), and it resists compression at 248, below the "at end"
  tag's 750, so O1's keyed row still narrows the field to show the tag
  whole (O8) and a text longer than the field scrolls inside it rather
  than widening the row. The marker name keeps its 120 pt floor. A
  `multiline: true` string was already the Text tab's `InspectorTextArea`,
  the row's full width and 72 pt tall, and is unchanged; it takes K-4's
  Return (⇧Return a new line). The clip header's name field was already
  pinned edge to edge and is unchanged.
- **G-49 — A `framejob://graphic?src=<https URL>` link makes Frame Job
  fetch a `.fjgraphic` itself and hand it to G-47's ask-first import**
  (#385; the owner, 2026-11-10: "begin all"). The link is input from the
  open web, so every part of it is refused unless it is exactly what is
  listed here.
  (a) **The link.** `<scheme>://graphic?src=<URL, percent-encoded>`, the
  scheme the bundle claims ((i)), any case. At most 2,048 bytes. The action
  (the link's host) is `graphic`, any case; any other is refused by name.
  No user name, password, port or fragment, and no path but an empty one or
  `/`. The query is exactly one `src`: none, a second one, or any other key
  is refused.
  (b) **`src`**, and every address a redirect names. Printable ASCII only
  (an international name is written in its `xn--` form), at most 2,048
  bytes. Scheme `https`, any case. No user name and no password. The host
  is the one the request is sent to (`URL.host`, percent-decoded),
  lowercased, and must be a public NAME: only letters, digits, hyphens and
  dots; two or more labels, none empty, so a trailing dot is refused; the
  last label neither all digits nor starting `0x` (WHATWG's test for an
  IPv4 literal; `2130706433` and `localhost` fall to the two-label rule,
  an IPv6 literal to the characters); and not ending in `.local`,
  `.localhost`, `.internal`, `.home.arpa`, `.lan` or `.home`. Any port.
  That one string is what is tested and what is shown.
  (c) **Private networks are refused by name, not by address.** (b)
  refuses every IP literal, every one-word name and every private suffix,
  in the link and at each redirect. A public name that RESOLVES to a
  private address is not detected: `URLSession` gives no address before the
  request is sent. Accepted, because the request is one GET with no cookie,
  no credential and no body, an answer is read only after a certificate the
  system trusts for that name, nothing of the answer goes back to the page,
  and the sheet names the host.
  (d) **The fetch.** One `GET` on an ephemeral session of its own: no
  cookies, no cache, no credential storage. Each redirect is held to (b);
  at most 5. Only status 200 is taken; `Content-Type` is ignored, because
  the core's reader decides (G-47 (c)). **One answer only:** a
  `multipart/x-mixed-replace` body reaches the session as a response per
  part, and the second is refused, so a fetch makes one folder and the
  bytes counted are the file's. **At most 32 MiB (33,554,432
  bytes)** as delivered: refused at the headers when the declared length is
  larger, and cut off when the body passes it. **30 s** with no byte and
  **120 s** in all. The body streams to `<temporary
  directory>/FrameJobLink-<UUID>/<name>`, where `<name>` is `src`'s last
  path component when it is 1 to 100 of letters, digits, space, `.`, `_`
  and `-`, does not start with a dot and ends `.fjgraphic`, else
  `graphic.fjgraphic`. The folder is removed once the package has been
  read into memory, or at any refusal.
  (e) **One at a time.** A link that arrives while a fetch runs is refused:
  "Frame Job is already fetching a graphic from `<host>`". The slot frees
  when the fetch ends, before the sheet.
  (f) **No question before the fetch and no progress.** The browser has
  asked "Open Frame Job?", the fetch is bounded by (d), and it ends in the
  sheet or an alert. Nothing is imported without the sheet's Import (G-47
  (f)), and every check of G-47 runs unchanged on the fetched file.
  (g) **The sheet's host line**, `graphicimport.origin`, under the
  description: `From: <host>`, or `From: <final host> (the link named
  <first host>)` when a redirect changed it. Hidden for the Finder door and
  From File….
  (h) **A refusal is one alert**, a sheet on the front project's window or,
  with none, application-modal, shown once launch has settled
  (`whenSettled`): "This link cannot be opened." before the fetch, "The
  graphic from `<host>` could not be opened." after it began, with the
  rule's sentence under it; a package the reader refuses keeps G-47's
  sentence there. A piece of the link quoted in a sentence is cut to 60
  characters. After the alert, when Frame Job has no project and no window
  (a link that launched it), the Welcome window is shown. The sentences:
  "the link is longer than 2,048 bytes" · "it is not a `<scheme>`:// link"
  · "Frame Job does not know the action "`<x>`"; the only one is graphic" ·
  "the link carries a user name or a password" · "the link carries a port"
  · "the link carries a path" · "the link carries a fragment" · "the link
  names no src" · "the link names src more than once" · "the link has a key
  other than src: "`<k>`"" · "`<what>` is not a URL in plain ASCII" ·
  "`<what>` is longer than 2,048 bytes" · "`<what>` must be an https URL" ·
  "`<what>` must not carry a user name or a password" · "`<what>` names
  "`<host>`", which is not a public host name; Frame Job fetches only from
  a named host on the internet, never an address, a one-word name or a
  private suffix" (`<what>` is `src` or `the redirect`) · "the server
  redirected more than 5 times" · "the server answered `<status>`, not 200"
  · "the server answered more than once"
  · "the file is `<n>` bytes; a graphic sent by link is at most
  33,554,432" · "the file is larger than 33,554,432 bytes" · "the server
  sent nothing for 30 s" · "the download took longer than 120 s" · "the
  connection failed: `<the system's words>`" · "the download could not be
  saved: `<the system's words>`".
  (i) **The claim.** `CFBundleURLTypes`: one row, `CFBundleURLName`
  `com.kgalligan.framejob-link`, role Viewer, schemes
  `[$(RC_LINK_SCHEME:default=framejob)]`. Debug sets `RC_LINK_SCHEME` to
  `framejob-debug` (V-5's pattern: Release and Distribution keep identical
  Info.plist bytes), so a Debug build never claims `framejob`; a URL type
  has no documented `LSHandlerRank`. No entitlement is added: the app is
  not sandboxed and already connects out in every configuration.
  (j) **The handler is an Apple Event handler**
  (`kInternetEventClass`/`kAEGetURL`), installed in
  `applicationWillFinishLaunching`. Never `application(_:open:)`: a
  delegate that implements it takes every Finder open away from
  `NSDocumentController`, which is every `.framejob` and `.fjgraphic` door
  (#234, G-47 (a)).
  (k) **No product tool.** `import_graphic {path}` stays the agent's door
  (G-47 (i)): a tool that fetched a URL would hand an agent a request
  forger. The tool counts and the parity check do not change.
  (l) **Dev only** (`FRAMEJOB_DEV_TOOLS`): the dev tool `open_link {url?,
  wait?}`, which hands the product's receiver a `kAEGetURL` event it built
  and answers the outcome in place of the alert and of nothing else
  (`sheet`, `refused` with the sentence, or `pending`; with no `url`, every
  earlier link's outcome), and the launch argument
  `-RCDevGraphicLinkLoopbackHTTP YES`, read from the argument domain only,
  with which `http://127.0.0.1` (that exact host, any port) passes (b) in
  the link and at a redirect. The member that carries the switch and the
  branch that reads it are not compiled in Distribution;
  `dist_check.py` (D44, D45) and `published_check.py` (P26) hold the
  switch's name out of that binary, and D46, D47 and P27 hold the claimed
  scheme to exactly `framejob`.
  (m) **Mutants: twenty-three**, over CLAUDE.md's ten, because the decisions
  here are refusals of hostile input and #385's batch asks one per refusal:
  twenty-two on `graphic_link_probe.py` (each a rebuild of three files) and
  one on the app (`graphic_link_proof.py`'s `loopback-always`). Refusals
  that share one: the link's user, port, path and fragment (one guard each,
  one mutant dropping the four); the other key and the repeated `src`. Not
  mutated: "the link names no src" (without the guard there is no address
  to go on with, so no mutant compiles to a different answer) and the two
  2,048-byte tests' twin on `src` (the link's own cap is reached first).
  A redirect to `file:` is refused by `URLSession` before the delegate is
  asked; the probe's row accepts either refusal and requires no file.
  **Accepted:** (c)'s resolving name; a quit during a fetch leaves its
  folder to the system's temporary-directory clean-up; what delivers the
  link (Launch Services, the Apple Event, the browser's question, a real
  certificate) is seen only by a person, GR-18.
