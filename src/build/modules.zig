//! Build modules shared across every kernel/bootloader target, real and
//! roadmap-stub alike: "common" (code shared between the bootloader and
//! kernel) and "abi" (Linux syscall/ABI-compatibility reference data, kept
//! separate since it's about an *external* contract, not shared code).

const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;

const docs_mod = @import("docs.zig");
const Docs = docs_mod.Docs;

/// Real architectures the "abi" module's reference data covers (see
/// src/abi/README.md) -- one doc-only build per entry, since Zig's autodoc
/// can only resolve one branch of a `builtin.cpu.arch`-keyed switch per
/// compilation (`syscall`/`auxv`/`fcntl`/`mman` in src/abi/root.zig,
/// `types.stat` in src/abi/types/root.zig). A single host-targeted doc build
/// would silently only ever document whichever architecture happens to
/// match the machine running `zig build docs` -- building one per real arch
/// instead means every architecture's actual (fully resolved) constants show
/// up somewhere, each under its own explicit `abi-<name>` doc page.
const abi_doc_targets = [_]struct { name: []const u8, query: Target.Query }{
    .{ .name = "x86_64", .query = .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none } },
    .{ .name = "aarch64", .query = .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none } },
    .{ .name = "arm", .query = .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .eabi } },
    .{ .name = "powerpc", .query = .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .eabi } },
};

const LoggerScpIgn: type = []const []const u8;

pub fn addCommon(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
) *Module {
    // Default set of scopes to ignore in the logger. -Dno-log-scope adds a
    // scope to the ignore list on top of this default and may be given
    // multiple times (e.g. -Dno-log-scope=arch_paging -Dno-log-scope=acpi_madt).
    // Passing it with no value (-Dno-log-scope=) clears the list, including
    // the defaults. -Dlog-scope removes a scope from the ignore list,
    // whitelisting it back out of the defaults or a -Dno-log-scope, and may
    // likewise be given multiple times.
    const default_no_log_scopes: LoggerScpIgn = &.{
        "arch_paging",
        "kp_alloc",
        "acpi",
        "arch_lapic",
        "arch_ioapic",
        "term_fbcon",
    };
    const no_log_scope_args = b.option(
        LoggerScpIgn,
        "no-log-scope",
        "Add a scope to ignore in the logger, on top of the default list (repeatable; pass with no value to clear the list, including defaults)",
    ) orelse &.{};
    const log_scope_args = b.option(
        LoggerScpIgn,
        "log-scope",
        "Remove a scope from the ignored-scope list, whitelisting it out of the defaults or -Dno-log-scope (repeatable)",
    ) orelse &.{};

    const reset_no_log_scopes = for (no_log_scope_args) |scope| {
        if (scope.len == 0) break true;
    } else false;

    var no_log_scopes = std.array_list.Managed([]const u8).init(b.allocator);
    if (!reset_no_log_scopes) no_log_scopes.appendSlice(default_no_log_scopes) catch @panic("OOM");
    for (no_log_scope_args) |scope| {
        if (scope.len == 0) continue;
        no_log_scopes.append(scope) catch @panic("OOM");
    }
    for (log_scope_args) |scope| {
        var i: usize = 0;
        while (i < no_log_scopes.items.len) {
            if (std.mem.eql(u8, no_log_scopes.items[i], scope)) {
                _ = no_log_scopes.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
    const logger_scopes_ignore: LoggerScpIgn = no_log_scopes.items;
    // const use_llvm: bool = b.option(bool, "use-llvm", "Use the LLVM backend for code generation (instead of the in-house solution)") orelse true;
    // const use_lld: bool = b.option(bool, "use-lld", "Use the LLD Linker for linking (instead of the in-house solution)") orelse true;
    // const debug_scheduler: bool = b.option(bool, "debug-scheduler", "Print out scheduler debug information") orelse false;

    // options module
    const options = b.addOptions();
    options.addOption(LoggerScpIgn, "logger_scopes_ignore", logger_scopes_ignore);
    // options.addOption(bool, "debug_scheduler", debug_scheduler);

    const common_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        // .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    common_mod.addOptions("build_options", options);

    // Same "docs-only, host-targeted" trick as `abi` below -- `common_mod`
    // has no fixed target of its own (only ever imported into other
    // target-specific modules), so it needs its own compile object to run
    // `getEmittedDocs()` against.
    const common_docs_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    common_docs_mod.addOptions("build_options", options);
    const common_docs_obj = b.addObject(.{
        .name = "common",
        .root_module = common_docs_mod,
    });
    docs.addModuleDocs(b, common_docs_obj, "common");

    return common_mod;
}

/// The "abi" module: Linux syscall/ABI compatibility reference data (see
/// src/abi/README.md). Kept separate from "common" -- it's reference data
/// about an *external* (Linux's) contract, not code shared between the
/// bootloader and kernel.
pub fn addAbi(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
) *Module {
    const abi_mod = b.createModule(.{
        .root_source_file = b.path("src/abi/root.zig"),
        .optimize = optimize,
    });

    // `abi_mod` above has no fixed target (it's only ever imported into
    // other target-specific modules), so it has nothing of its own to run
    // `getEmittedDocs()` against. Build one docs-only object per real
    // architecture instead of a single host-targeted one -- see
    // `abi_doc_targets`'s doc comment for why.
    for (abi_doc_targets) |target| {
        const abi_docs_mod = b.createModule(.{
            .root_source_file = b.path("src/abi/root.zig"),
            .target = b.resolveTargetQuery(target.query),
            .optimize = optimize,
        });
        const abi_docs_obj = b.addObject(.{
            .name = b.fmt("abi-{s}", .{target.name}),
            .root_module = abi_docs_mod,
        });
        docs.addModuleDocs(b, abi_docs_obj, b.fmt("abi-{s}", .{target.name}));
    }

    return abi_mod;
}
