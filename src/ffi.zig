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

pub export fn node_free(node: ?*anyopaque) i32 {
  const elem:*Element = @ptrCast(@alignCast(node));
  elem.deinit();
  global_allocator.destroy(elem);
  return 0;
}

pub export fn node_type(node: ?*anyopaque) i32 {
  const elem:*Element = @ptrCast(@alignCast(node));
  std.debug.print("Debug: Actual nodeType value is {d}\n", .{@intFromEnum(elem.nodeType)});
  return @intFromEnum(elem.nodeType);
}

// return a copy of the string not a reference
pub export fn node_name(node: *anyopaque) [*c]u8 {
    const elem:*Element = @ptrCast(@alignCast(node));
    const c_str = global_allocator.dupeZ(u8, elem.tagName) catch return null;
    return @as([*c]u8, c_str.ptr);  // Returns a C string that needs to be freed by the caller
}

const testing = std.testing;

test "ffi_node" {
    // Test that node_create returns a valid pointer and node_free works without crashing
    const tag_name = "test_node";
    const elem_ptr = node_create(tag_name.ptr);
    try testing.expect(elem_ptr != null);

    // Test node_type
    const type_value = node_type(elem_ptr);
    try testing.expectEqual(@as(i32, 1), type_value);  // Expecting element_node which is 1

    // Test node_name
    const name_ptr = node_name(elem_ptr.?);
    if (name_ptr != null) {
        const name = std.mem.span(name_ptr);
        try testing.expect(std.mem.eql(u8, name, tag_name));
        // Free the allocated string
        const allocator = std.heap.page_allocator;
        allocator.free(name);
    }

    const free_result = node_free(elem_ptr);
    try testing.expectEqual(@as(i32, 0), free_result);
}
