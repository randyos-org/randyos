# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## What this is

RandyOS is a from-scratch, multi-arch OS fork of [zig_os](https://codeberg.org/sfiedler/zig_os) and
[loup-os](https://codeberg.org/loup-os), built with Zig. See `readme.md` for the target-machine matrix.
Only the x86_64 PC/Mac path (UEFI bootloader + freestanding kernel) is actually working; every other
architecture in `src/kernel/arch/` and every `src/bootloader-*/` directory is a compile-only roadmap
stub (see the `ArchStub` doc comment in `build.zig` and `src/abi/README.md`).

Don't try to "finish" a stub arch unless explicitly asked — the stub existing and compiling *is* the
current milestone for that arch.

## Repo layout

- `src/common/` — code shared between the bootloader and kernel modules (`common` module, imported by both).
- `src/bootloader/` — the real, working UEFI bootloader (x86_64/aarch64 target queries via `build.zig`).
- `src/bootloader-rpi/`, `src/bootloader-asahi/`, `src/bootloader-ofw/` — stub notes for boot paths with
  no working UEFI story yet (Pi 5, Apple Silicon, PowerPC Open Firmware). Read the file-level doc
  comment before touching these; they're intentionally unimplemented.
- `src/kernel/` — the real kernel, with `src/kernel/arch/<name>/` per-architecture code. Only `x86_64`
  is wired into the default build/install/QEMU pipeline; `aarch64`, `arm`, `powerpc` are stub-only.
- `src/abi/` — Linux syscall ABI-compatibility roadmap notes (musl target libc, per-arch syscall number
  tables mechanically extracted from the Linux kernel source, **not hand-typed**). Nothing here is wired
  to a dispatcher yet. Read `src/abi/README.md` before editing anything under `src/abi/syscall/`; if a
  table ever needs refreshing, re-fetch the Linux source file and re-run extraction rather than
  hand-editing numbers.
- `build.zig` — single build script for everything above; see its doc comments for the sysroot/QEMU/OVMF
  plumbing and the `ArchStub` mechanism used to add new roadmap-stub architectures.
- `kernel/` and `kernel-dev/` — **local-only reference copies** of the upstream loup-os/zig_os trees,
  excluded from git via `.local-gitignore` (not tracked, not part of this repo). They're kept around for
  cross-referencing during the port/rewrite (e.g. `kernel-dev/build.zig` shows a `zig build test`/`check`
  step and `test_main.zig` runner that `build.zig` at the repo root hasn't ported over yet). Don't treat
  them as part of the codebase to edit, and don't assume they reflect what's committed here.
  - `kernel-dev/` contains GPL3 code, while `kernel/` is the MIT version before it was re-licensed to GPL3.  Ensure that any consultation of the `kernel-dev/` directory is conceptual in nature only.  I tried my best to port some of the newer features and improvements myself, most of which were trivial adaptations to newer Zig syntax/stdlib, but be on the lookout for more blatant violations and work to flag or remove them.  We are MIT licensed, so don't risk GPL3 poisoning!

## Build & run

- `zig build` (default step) — builds the x86_64 PC/Mac bootloader + kernel and stages them into the
  sysroot.
- `zig build kernel-<arch>` / `zig build boot-<arch>` (`aarch64`, `arm`, `powerpc`) — compile-only stub
  targets; they don't touch the default install step, sysroot, or QEMU pipeline.
- `zig build run` / `zig build debug` — raw QEMU invocations (debug waits for a GDB connection on
  `localhost:1234`).
- `zig build monitor` — attach to the QEMU monitor socket via `socat`.
- `zig build docs` — generate API docs (Zig's built-in autodoc, extracted from `///`/`//!` comments) for
  the bootloader and kernel separately, installed to `zig-out/docs/bootloader/` and `zig-out/docs/kernel/`
  respectively (each has its own `index.html`). This also runs automatically as part of the default
  `zig build`/`zig build install` step -- no separate invocation needed for docs to stay current. The
  roadmap arch stubs (`kernel-<arch>`/`boot-<arch>`) don't get docs generated for them.
- There is currently no `zig build test`/`check` step wired up at the repo root (unlike the reference
  trees in `kernel-dev/`). Don't assume `zig build test` works until that's ported.

## Zig version

Treat **Zig `0.17.0-dev.203`** as the API baseline for anything in this repo (std lib surface, `Build`
API shape, language features) unless told otherwise. The `.zigversion` file is git-ignored and reflects
whatever toolchain happens to be installed locally, which may be a *newer* dev snapshot than the assumed
baseline — don't let a newer local `.zigversion` justify using APIs that post-date `0.17.0-dev.203`. If
you're unsure whether something is available at that version, say so rather than guessing.

On my local machine, this is housed currently at `/c/scratch/git/zig-build/devkit-0.17.0-dev.203+073889523/bin/zig.exe`

## Markdown

There must never be markdownlint warnings or errors, in this file or any other Markdown file in the
repo. Config lives in `.markdownlint.jsonc` (rule overrides) and `.markdownlint-cli2.jsonc`. Before
finishing any task that touches a `.md` file, run:

```bash
npx markdownlint-cli2 "**/*.md"
```

Fix everything it reports — don't add rule suppressions to get around a finding unless the user
asks for it.

## Style conventions

- Indentation: 4 spaces for `.zig`/`.py`, 2 spaces otherwise, LF line endings, trailing whitespace
  trimmed, final newline required (`.editorconfig` is authoritative — don't fight it).
- File naming: PascalCase filenames (`Terminal.zig`, `Graphics.zig`) for files whose main export is a
  single type/struct meant to be imported as that type; lowercase filenames (`acpi.zig`, `debug.zig`,
  `memory.zig`) for module-style files exposing multiple declarations.
- Doc comments: `//!` file-level doc comments explaining *why* a file exists and any non-obvious
  provenance/rationale (this codebase leans heavily on this for stub/roadmap files — see
  `src/bootloader-rpi/main.zig` or `src/abi/syscall/x86_64.zig` for the expected level of detail);
  `///` for public declarations. Follow the "why, not what" comment philosophy throughout — don't narrate
  what code obviously does.
- When a file's data is mechanically derived from an external source (e.g. Linux syscall tables), the
  doc comment must say where it came from (exact source file, commit/tag) and that it should be
  re-derived rather than hand-edited if it goes stale.

## Spelling

`.cspell.jsonc` drives spell-checking; project-specific words go in
`.vscode/ltex.dictionary.en-US.txt` rather than being added as inline ignores, unless there's a good
reason to scope it more narrowly.  Do not add words to the dictionary yourself.
