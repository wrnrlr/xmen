const std = @import("std");
const dom = @import("./dom.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const Element = dom.Element;
const Document = dom.Document;
const Text = dom.Text;
const Attr = dom.Attr;
const NodeType = dom.NodeType;

const global_allocator = std.heap.page_allocator;

pub export fn doc_init() ?*Node {
    const node = global_allocator.create(Node) catch return null;
    const doc = global_allocator.create(Document) catch {
      global_allocator.destroy(node);
      return null;
    };
    doc.* = Document.init(global_allocator);
    node.* = Node{ .document = doc };
    return node;
}

pub export fn elem_init(buf: [*c]const u8, len: usize) ?*Node {
    const node = global_allocator.create(Node) catch return null;
    const elem = global_allocator.create(Element) catch {
      global_allocator.destroy(node);
      return null;
    };
    elem.* = Element.init(global_allocator, buf[0..len]);
    node.* = Node{ .element = elem };
    return node;
}

pub export fn node_free(ptr: ?*anyopaque) i32 {
  if (ptr == null) return 0;
  const node:*Node = @ptrCast(@alignCast(ptr));
  node.deinit();
  global_allocator.destroy(node);
  return 0;
}

pub export fn node_type(node: ?*anyopaque) u8 {
    if (node) |ptr| {
        const n: *Node = @ptrCast(@alignCast(ptr));
        return @intFromEnum(n.getNodeType());
    }
    return 0;
}

pub export fn tag_name(node: *anyopaque) [*c]u8 {
    const n:*Node = @ptrCast(@alignCast(node));
    const c_str = global_allocator.dupeZ(u8, n.element.tagName) catch return null;
    return @as([*c]u8, c_str.ptr);
}

const testing = std.testing;

test "ffi doc_init" {
    const ptr = doc_init();

    try testing.expectEqual(@as(u8, @intFromEnum(NodeType.document)), node_type(ptr));
    try testing.expectEqual(@as(i32, 0), node_free(ptr));
}

test "ffi elem_init" {
  var tag = "a";
  const ptr = elem_init(@as([*c]const u8, &tag[0]), tag.len);

  try testing.expectEqual(@as(u8, @intFromEnum(NodeType.element)), node_type(ptr));
  try testing.expectEqual(@as(i32, 0), node_free(ptr));
}
