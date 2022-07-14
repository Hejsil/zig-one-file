const std = @import("std");

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const json = std.json;
const math = std.math;
const mem = std.mem;
const process = std.process;
const zig = std.zig;

pub fn main() anyerror!void {
    var global_arena_state = heap.ArenaAllocator.init(heap.page_allocator);
    const global_arena = global_arena_state.allocator();
    defer global_arena_state.deinit();

    var packages = std.StringHashMap([]const u8).init(global_arena);

    const args = try process.argsAlloc(global_arena);
    var i: usize = 1;
    while (i < args.len) : (i += 1) {}

    var global_indexs = std.StringHashMap(usize).init(global_arena);
    var files = std.ArrayList([]const u8).init(global_arena);
    var output = std.ArrayList(u8).init(global_arena);

    const writer = output.writer();

    const first_file_path = try std.fs.cwd().realpathAlloc(global_arena, args[i - 1]);
    try files.append(first_file_path);
    try global_indexs.putNoClobber(first_file_path, 0);

    try writer.writeAll(
        \\comptime { _ = __import_0; }
    );

    while (files.popOrNull()) |file_path| {
        var loop_arena_state = heap.ArenaAllocator.init(heap.page_allocator);
        const loop_arena = loop_arena_state.allocator();
        defer loop_arena_state.deinit();

        const index = global_indexs.get(file_path).?;
        try writer.print("const __import_{} = struct {{\n", .{index});

        const file_dir_path = fs.path.dirname(file_path) orelse ".";
        const file_name = fs.path.basename(file_path);
        var dir = try fs.openDirAbsolute(file_dir_path, .{});
        defer dir.close();

        const file_content = try dir.readFileAllocOptions(
            loop_arena,
            file_name,
            math.maxInt(u32),
            null,
            1,
            0,
        );

        var start: usize = 0;
        var tokenizer = zig.Tokenizer.init(file_content);
        while (true) {
            const token = tokenizer.next();
            switch (token.tag) {
                .eof => break,
                .invalid, .invalid_periodasterisks => return error.InvalidSyntax,
                .builtin => {},
                else => continue,
            }
            if (!mem.eql(u8, file_content[token.loc.start..token.loc.end], "@import"))
                continue;

            const l_paren = tokenizer.next();
            if (l_paren.tag != .l_paren)
                return error.InvalidSyntax;

            const string = tokenizer.next();
            if (string.tag != .string_literal)
                return error.InvalidSyntax;

            const r_paren = tokenizer.next();
            if (r_paren.tag != .r_paren)
                return error.InvalidSyntax;

            const import_path = try zig.string_literal.parseAlloc(
                loop_arena,
                file_content[string.loc.start..string.loc.end],
            );
            if (mem.eql(u8, import_path, "root") or
                mem.eql(u8, import_path, "builtin") or
                mem.eql(u8, import_path, "std"))
                continue;

            const real_import_path = dir.realpathAlloc(global_arena, import_path) catch blk: {
                break :blk packages.get(import_path) orelse return error.InvalidPackage;
            };
            try global_indexs.ensureUnusedCapacity(1);
            try files.ensureUnusedCapacity(1);

            const entry = global_indexs.getOrPutAssumeCapacity(real_import_path);
            if (!entry.found_existing) {
                files.appendAssumeCapacity(real_import_path);
                entry.value_ptr.* = global_indexs.count() - 1;
            }

            try writer.writeAll(file_content[start..token.loc.start]);
            try writer.print("__import_{}", .{entry.value_ptr.*});
            start = r_paren.loc.end;
        }

        try writer.writeAll(file_content[start..]);
        try writer.writeAll("};\n");
    }

    try std.io.getStdOut().writeAll(output.items);
}
