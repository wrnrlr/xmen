const std = @import("std");
const dom = @import("./dom.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const Element = dom.Element;
const Document = dom.Document;
const Text = dom.Text;
const Attr = dom.Attr;

const global_allocator = std.heap.page_allocator;

// Only support creating a new Element for now
pub export fn node_create(tag_name: [*c]const u8) ?*Element {
    const tag = std.mem.span(tag_name);
    const elem = global_allocator.create(Element) catch return null;
    elem.* = Element.init(global_allocator, tag);
    return elem;
}

//
pub export fn node_free(node: ?*anyopaque) i32 {
    if (node) |n| {
        const elem:*Element = @ptrCast(@alignCast(n));
        const allocator = std.heap.page_allocator;
        elem.deinit();
        allocator.destroy(elem);
        return 0;
    } else {
        return 1;  // Error code, e.g., null node
    }
}

pub export fn node_type(node: ?*anyopaque) i32 {
  const n:*Node = @ptrCast(@alignCast(node));
  return @intFromEnum(n.getNodeType());
}

// return a copy of the string not a reference
pub export fn node_name(node: *anyopaque) [*c]u8 {
    const elem:*Element = @ptrCast(@alignCast(node));
    const allocator = std.heap.page_allocator;
    const c_str = allocator.dupeZ(u8, elem.tagName) catch return null;
    return @as([*c]u8, c_str.ptr);  // Returns a C string that needs to be freed by the caller
}

const testing = std.testing;

test "ffi_node" {
    // Test that node_create returns a valid pointer and node_free works without crashing
    const tag_name = "test_node";
    const elem_ptr = node_create(tag_name.ptr);
    try testing.expect(elem_ptr != null);
    // Cast to anyopaque for node_free
    std.debug.print("Debug: Before node_free, tagName address is {*}\n", .{elem_ptr.?.tagName.ptr});
    const result = node_free(@ptrCast(elem_ptr));
    try testing.expectEqual(@as(i32, 0), result);
}
