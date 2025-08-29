const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const None: u32 = std.math.maxInt(u32);
pub const Root: u32 = 0;

const StringPool = struct {
    strings: ArrayList([]const u8),
    map: std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .strings = ArrayList([]const u8).init(allocator),
            .map = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.strings.items) |str|
            self.strings.allocator.free(str);
        self.strings.deinit();
        self.map.deinit();
    }

    pub fn intern(self: *Self, str: []const u8) !u32 {
        if (self.map.get(str)) |id|
            return id;
        const owned_str = try self.strings.allocator.dupe(u8, str);
        const id: u32 = @intCast(self.strings.items.len);
        try self.strings.append(owned_str);
        try self.map.put(owned_str, id);
        return id;
    }

    pub fn getString(self: *const Self, id: u32) []const u8 {
        return self.strings.items[id];
    }
};
