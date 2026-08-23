# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## What this is

RandyOS is a from-scratch, multi-arch OS built with Zig. See `readme.md` for the target-machine matrix.

## Build & run

- `zig build` (default step) — builds the x86_64 PC/Mac bootloader + kernel and stages them into the
  sysroot.
- `zig build kernel-<arch>` / `zig build boot-<arch>` (`aarch64`, `arm`, `powerpc`) — compile-only stub
  targets; they don't touch the default install step, sysroot, or QEMU pipeline.
- `zig build run` / `zig build debug` — raw QEMU invocations (debug waits for a GDB connection on
  `localhost:1234`).
- `zig build monitor` — attach to the QEMU monitor socket via `socat`.
- There is currently no `zig build test`/`check` step wired up at the repo root (unlike the reference
  trees in `kernel-dev/`). Don't assume `zig build test` works until that's ported.
- `zig` is not on `PATH` in this environment. The self-built toolchain lives at
  `C:\scratch\git\zig-build\bin\stage4\bin\zig.exe` (std lib at `C:\scratch\git\zig-build\lib\std`);
  invoke it by full path.

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

- `.editorconfig` is authoritative — don't fight it.
- File naming: PascalCase filenames (`Terminal.zig`, `Graphics.zig`) for files whose main export is a
  single type/struct meant to be imported as that type; lowercase filenames (`acpi.zig`, `debug.zig`,
  `memory.zig`) for module-style files exposing multiple declarations.
- When a file's data is mechanically derived from an external source (e.g. Linux syscall tables), the
  doc comment must say where it came from (exact source file, commit/tag) and that it should be
  re-derived rather than hand-edited if it goes stale.

## Git

- Never run `git add` (or otherwise stage) after making edits, and never assume staging is a safe
  default just because committing isn't happening. Leave the working tree with unstaged changes, so
  the user can review them as an unstaged diff — auto-staged files disappear from that view, which
  reads as files randomly going missing mid-review. Only stage when explicitly asked to stage or
  commit.
- Never commit, pull, or perform any other sort of git operation with side effects unless explicitly asked to do so.  Checking git log or git diff are ok, changing branches or pushing are not.

## Spelling

`.cspell.jsonc` drives spell-checking; project-specific words go in
`.vscode/ltex.dictionary.en-US.txt` rather than being added as inline ignores, unless there's a good
reason to scope it more narrowly.  Do not add words to the dictionary yourself.
