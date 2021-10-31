const std = @import("std");
const Allocator = std.mem.Allocator;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = &arena.allocator;

const States = enum {
    initial,
    maybeStartTagBlock,
    scanningTag,
    maybeEndTagBlock,
};

const State = union(States) {
    initial: void,
    maybeStartTagBlock: void,
    scanningTag: usize,
    maybeEndTagBlock: usize,
};

const Range = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Range {
        return .{ .start = start, .end = end };
    }
};

fn scanContexts(contents: []const u8) ![]Range {
    const file = contents;
    var tags = std.ArrayList(Range).init(allocator);
    var cur: usize = 0;
    var state = State{ .initial = undefined };

    while (cur < file.len) {
        var c = file[cur];
        cur += 1;

        // TODO: Allow numbers!
        switch (c) {
            '\n' => {
                switch (state) {
                    .initial => {},
                    .maybeStartTagBlock => {
                        state = State{ .initial = undefined };
                    },
                    .scanningTag => {
                        state = State{ .initial = undefined };
                    },
                    .maybeEndTagBlock => |v| {
                        try tags.append(Range.init(v, cur - 2));
                        state = State{ .initial = undefined };
                    },
                }
            },
            ':' => {
                switch (state) {
                    .initial => {
                        state = State{ .maybeStartTagBlock = undefined };
                    },
                    .maybeStartTagBlock => {},
                    .scanningTag => |v| {
                        state = State{ .maybeEndTagBlock = v };
                    },
                    .maybeEndTagBlock => {},
                }
            },
            'a'...'z', 'A'...'Z', '-', '_' => {
                switch (state) {
                    .initial => {},
                    .maybeStartTagBlock => {
                        state = State{ .scanningTag = cur - 1 };
                    },
                    .scanningTag => {},
                    .maybeEndTagBlock => |v| {
                        try tags.append(Range.init(v, cur - 2));
                        state = State{ .scanningTag = cur - 1 };
                    },
                }
            },
            else => {
                // TODO: add case of numbers here?J
                switch (state) {
                    .initial => {},
                    .maybeStartTagBlock => {
                        state = State{ .initial = undefined };
                    },
                    .scanningTag => {
                        // tar syntax error; abort!
                        state = State{ .initial = undefined };
                    },
                    .maybeEndTagBlock => |v| {
                        try tags.append(Range.init(v, cur - 2));
                        state = State{ .initial = undefined };
                    },
                }
            },
        }
    }

    return tags.items;
}

fn scanContextsForFile(filename: []const u8) !void {
    const file = try std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024 * 1024);

    var items = try scanContexts(file);

    for (items) |range| {
        try stdout.print("{s}\n", .{file[range.start..range.end]});
    }
}

pub fn getNextArg(it: anytype) ![]u8 {
    if (it.next(allocator)) |arg| {
        var str = try arg;

        return str;
    } else {
        return error.NoArg;
    }
}

fn usage() !void {
    try stderr.writeAll("Usage: cabined-scan [mode] [filename]\n\n");
    try stderr.writeAll("Available modes: \n");
    try stderr.writeAll("\ttags\n");
    try stderr.writeAll("\tcontexts\n");
}

pub fn main() anyerror!void {
    defer arena.deinit();

    var argsIt = std.process.args();
    _ = argsIt.skip();

    var mode = getNextArg(&argsIt) catch {
        try usage();
        std.os.exit(1);
    };
    var filename = getNextArg(&argsIt) catch {
        try usage();
        std.os.exit(1);
    };

    if (std.mem.eql(u8, mode, "tags")) {
        try stderr.writeAll("Not implemented yet!\n");
        std.os.exit(1);
    } else if (std.mem.eql(u8, mode, "contexts")) {
        try scanContextsForFile(filename);
    } else {
        try usage();
        std.os.exit(1);
    }
}

const expect = std.testing.expect;

test "scanContexts" {
    // TODO: this fails for ":tag:tag:tag:"
    var text = " :tag:tag:tag: ";

    var items = try scanContexts(text);
    std.log.info("{}", .{items.len});
    try expect(items.len == 3);
}
