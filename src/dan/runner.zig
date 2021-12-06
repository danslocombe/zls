const std = @import("std");
const lines_lib = @import("lines.zig");
const Lines = lines_lib.Lines;
const Allocator = std.mem.Allocator;

pub fn hack_url_decode(allocator : Allocator, input : []const u8) ![]const u8 {
    return std.mem.replaceOwned(u8, allocator, input, "%3A", ":");
}

pub fn ast_check(allocator : Allocator, path : []const u8) !std.ArrayList(ParsedError) {
    var no_prefix = try std.mem.replaceOwned(u8, allocator, path, "file:///", "");
    var no_url_encode = try hack_url_decode(allocator, no_prefix);
    var parsed_path = try std.mem.replaceOwned(u8, allocator, no_url_encode, "/", "\\");

    //var file = try std.fs.createFileAbsolute("C:\\users\\dan\\tmp\\zls.log", .{.truncate = false});
    //try file.writer().print("Parsed path as '{s}'", .{parsed_path});
    //defer(file.close());

    var result = try std.ChildProcess.exec(.{.allocator = allocator, .argv = &.{"zig", "ast-check", parsed_path}});

    var lines = try Lines.init(allocator, result.stderr);

    var res = std.ArrayList(ParsedError).init(allocator);

    //try file.writer().print("stderr '{s}'", .{result.stderr});
    //std.log.info("{s}\n", .{result.stderr});

    var cursor : usize = 0;
    while (parse_error(allocator, lines, &cursor)) |parsed| {
        try res.append(parsed);
    }

    //try file.writer().print("Parsed '{d}' errors", .{res.items.len});

    return res;
}

pub const ParsedError = struct {
    line_number : u32,
    char_number : u32,

    error_str : []const u8,
    helper_str : []const u8,
};

fn parse_error(allocator : Allocator, lines : Lines, cursor : *usize) ?ParsedError {
    std.mem.doNotOptimizeAway(allocator);

    while (true)
    {
        var cur_line = lines.get(cursor.*);
        if (cur_line == null) {
            return null;
        }

        cursor.* += 1;

        // HACKY
        if (std.mem.startsWith(u8, cur_line.?, "c:\\")) {
            var splits = std.mem.split(u8, cur_line.?, " ");
            var path = splits.next();
            var typetype = splits.next();

            var text_start_index = splits.index;
            var text = splits.next();

            if (path == null or typetype == null or text == null)
            {
                continue;
            }

            if (!std.mem.startsWith(u8, typetype.?, "error")) {
                continue;
            }

            const pos = parse_position_from_path(path.?);
            if (pos == null) {
                continue;
            }

            const full_text = cur_line.?[text_start_index.?..];

            return ParsedError {
                .line_number = pos.?.line,
                .char_number = pos.?.char,
                .error_str = full_text,
                .helper_str = "",
            };
        }
        else {
            continue;
        }
    }
}

const Pos = struct {line : u32, char: u32};

// Expect path to be of the form C:\aowifjawoifja\main.zig:5:9:
fn parse_position_from_path(path : [] const u8) ?Pos {
    var splits = std.mem.split(u8, path, ":");

    var line_pos : ?[]const u8 = null;
    var char_pos : ?[]const u8 = null;

    while (splits.next()) |str| {
        if (str.len > 0) {
            line_pos = char_pos;
            char_pos = str;
        }
    }

    if (line_pos == null or char_pos == null) {
        return null;
    }

    const line = std.fmt.parseUnsigned(u32, line_pos.?, 10) catch { return null; };
    const char = std.fmt.parseUnsigned(u32, char_pos.?, 10) catch { return null; };

    return Pos{.line = line-1, .char = char-1 };
}
