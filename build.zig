const std = @import("std");

const assets_dir = "assets";
const source_dir = "source";
const templs_dir = "templs";
const output_dir = "output";

pub fn build(b: *std.Build) !void {
    const steps = blk: {
        var steps: [command_list.len]*std.Build.Step = undefined;
        inline for (0.., command_list) |i, cmd| {
            steps[i] = b.step(cmd[0], cmd[1]);
        }
        break :blk steps;
    };

    const target = b.standardTargetOptions(.{});
    const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
    const optimize = b.standardOptimizeOption(.{});

    const cli_exe = b.addExecutable(.{
        .name = "build_tool",
        .target = target,
        .version = version,
        .optimize = optimize,
        .root_source_file = b.path("build.zig"),
    });
    _ = cli_exe;

    inline for (0.., steps) |i, step| {
        //b.fmt("{s}", .{@tagName(@as(Command, @enumFromInt(i)))});
        switch (@as(Command, @enumFromInt(i))) {
            .build => {
                //std.debug.print("Build", .{});

                //step.dependOn();
            },
            .clean => {
                step.dependOn(&b.addRemoveDirTree(b.pathFromRoot(output_dir)).step);
            },
            .local => {},
            .host => {},
            .server => {},
            .run => {
                //const cli = b.addSystemCommand(&.{ "tetra", "parse" });
                //cli.addFileArg(b.path("build.zig"));
                //const output = cli.captureStdOut();
                //step.dependOn(&b.addInstallFileWithDir(output, .prefix, "test.txt").step);
                //step.dependOn(&cli);
                //defer walker.deinit();
                try build_site(b, step);
                step.dependOn(steps[@intFromEnum(Command.clean)]);
            },
        }
    }
}

const Entry = struct {
    path: []const u8 = "",
    basename: []const u8 = "",
};
const LANG_LIST = &[_][]const u8{ "en", "zh" };

fn build_template(b: *std.Build, step_top_level: *std.Build.Step, source_list: []const Entry, template: Entry) !void {
    const env = Env{};

    const page_id = "{{NAME}}";
    const lang_id = "{{LANG}}";
    const name_count = std.mem.count(u8, template.path, page_id);
    const lang_count = std.mem.count(u8, template.path, lang_id);

    const page_list: []const Entry = if (name_count > 0) source_list else &.{Entry{}};
    const lang_list: []const []const u8 = if (lang_count > 0) LANG_LIST else &.{""};
    for (lang_list) |lang| {
        for (page_list) |page| {
            const page_stem = page.basename[0 .. page.basename.len - std.fs.path.extension(page.basename).len];

            const source_path: []const u8 = if (0 == lang_count) template.path else blk: {
                var buf = try std.ArrayList(u8).initCapacity(b.allocator, template.path.len - lang_id.len * lang_count + lang.len);
                buf.expandToCapacity();
                _ = std.mem.replace(u8, template.path, lang_id, lang, buf.items);
                break :blk buf.items;
            };
            const output_path: []const u8 = if (0 == name_count) source_path else blk: {
                var buf = try std.ArrayList(u8).initCapacity(b.allocator, template.path.len - lang_id.len * lang_count + lang.len - page_id.len * name_count + page_stem.len);
                buf.expandToCapacity();
                _ = std.mem.replace(u8, source_path, page_id, page_stem, buf.items);
                break :blk buf.items;
            };
            const msg = b.addSystemCommand(&.{ "printf", "%s\\n", b.fmt("{s}: {s} -> {s}\n", .{ template.path, source_path, output_path }) });
            step_top_level.dependOn(&msg.step);

            const cli = b.addSystemCommand(&.{ "tetra", "parse" });
            cli.addFileArg(b.path(b.pathJoin(&.{ env.templs_dir, template.path })));
            cli.setEnvironmentVariable("SITE_ROOT", env.root_dir);
            cli.setEnvironmentVariable("SITE_SRC_PATH", b.pathJoin(&.{ env.source_dir, source_path }));
            cli.setEnvironmentVariable("SITE_DOMAIN", env.domain);
            cli.setEnvironmentVariable("SITE_ENDPOINT", template.path);
            cli.setEnvironmentVariable("SITE_LANGUAGE", lang);

            const output = cli.captureStdOut();
            step_top_level.dependOn(&b.addInstallFileWithDir(output, .{ .custom = env.output_dir }, output_path).step);
            //std.debug.print("{d} {s}\n", .{ lang_count + name_count, source_path });
        }
    }
}

fn build_site(b: *std.Build, step_top_level: *std.Build.Step) !void {
    const env = Env{};

    const source_list = blk: {
        var dir = try std.fs.cwd().openDir(env.source_dir, .{ .iterate = true, .no_follow = false });
        defer dir.close();
        var walker = try dir.walk(b.allocator);
        //defer walker.deinit();

        var list = try std.ArrayList(Entry).initCapacity(b.allocator, 1000);
        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .directory => {},
                .file => {
                    try list.append(.{ .path = entry.path, .basename = entry.basename });
                    ////const parse = b.addSystemCommand(&.{ "tetra", "parse" });
                    //const path = b.pathJoin(&[_][]const u8{ source_dir, entry.path });
                    //std.debug.print("{s}\n", .{path});
                    //step.dependOn(&parse.step);
                },
                else => std.debug.print("The inode type '{s}' is an unsupported in your source directory for the file '{s}'", .{ @tagName(entry.kind), entry.path }),
            }
        }
        break :blk list;
    };

    {
        var dir = try std.fs.cwd().openDir(env.templs_dir, .{ .iterate = true, .no_follow = false });
        defer dir.close();
        var walker = try dir.walk(b.allocator);
        //defer walker.deinit();

        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .directory => {},
                .file => try build_template(b, step_top_level, source_list.items, .{ .path = entry.path, .basename = entry.basename }),
                else => std.debug.print("The inode type '{s}' is an unsupported in your templates directory for the file '{s}'", .{ @tagName(entry.kind), entry.path }),
            }
        }
    }
}

const Env = struct {
    root_dir: []const u8 = "",
    source_dir: []const u8 = "source",
    templs_dir: []const u8 = "templs",
    output_dir: []const u8 = "public",
    domain: []const u8 = "",
};

//// run: zig run % -- build '{"source_dir":"source", "templs_dir": "templs"}'
//pub fn main() !void {
//    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//    //defer arena_instance.deinit();
//    const arena = arena_instance.allocator();
//
//    // Parse args into string array (error union needs 'try')
//
//    const args = blk: {
//        var args = try std.process.argsAlloc(arena);
//        var j: u16 = 0;
//        for (args) |arg| {
//            if (!std.mem.eql(u8, "--", arg)) {
//                args[j] = arg;
//                j += 1;
//            }
//        }
//        args = args[0..j];
//        break :blk args;
//    };
//
//    if (args.len < 1) {
//        std.debug.print("Provide more arguments\n", .{});
//        std.process.exit(1);
//    } else if (std.mem.eql(u8, "stderr", args[1])) {
//        std.debug.print("{s}", .{args[2]});
//    } else if (std.mem.eql(u8, "build", args[1])) {
//        const env = try std.json.parseFromSliceLeaky(Env, arena, args[2], .{});
//
//        var pages = try std.ArrayList(struct { []const u8, []const u8 }).initCapacity(arena, 1024);
//        {
//            var dir = try std.fs.cwd().openDir(env.source_dir, .{ .iterate = true, .no_follow = false });
//            defer dir.close();
//            var walker = try dir.walk(arena);
//            //defer walker.deinit();
//            while (try walker.next()) |entry| {
//                try pages.append(.{ entry.path, std.fs.path.stem(entry.path) });
//            }
//        }
//        {
//            var dir = try std.fs.cwd().openDir(env.templs_dir, .{ .iterate = true, .no_follow = false });
//            defer dir.close();
//            var walker = try dir.walk(arena);
//            //defer walker.deinit();
//            while (try walker.next()) |entry| {
//                std.debug.print("{s}\n", .{entry.path});
//            }
//        }
//    } else {
//        std.debug.panic("Unknown command: {s}\n", .{args[1]});
//    }
//}

const command_list = [_]struct { [:0]const u8, []const u8 }{
    .{ "build", "" },
    .{ "clean", "" },
    .{ "local", "" },
    .{ "host", "" },
    .{ "server", "" },
    .{ "run", "" },
};

const Command = @Type(std.builtin.Type{ .Enum = .{
    .tag_type = u3,
    .decls = &.{},
    .fields = blk: {
        var variants: [command_list.len]std.builtin.Type.EnumField = undefined;
        for (0.., command_list) |i, entry| {
            variants[i] = .{
                .name = entry[0],
                .value = i,
            };
        }
        break :blk &variants;
    },
    .is_exhaustive = true,
} });
