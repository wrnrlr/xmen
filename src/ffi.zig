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

pub export fn attr_init(name: [*c]const u8, name_len: usize, value: [*c]const u8, value_len: usize) ?*Node {
  const node = global_allocator.create(Node) catch return null;
  const attr = global_allocator.create(Attr) catch {
    global_allocator.destroy(node);
    return null;
  };
  attr.* = Attr{ .name = name[0..name_len], .value = value[0..value_len]};
  node.* = Node{ .attribute = attr };
  return node;
}

pub export fn attr_set(elem: ?*anyopaque, name: [*c]const u8, name_len: usize, value: [*c]const u8, value_len: usize) ?*Node {
    if (elem) |ePtr| {
        const elemNode: *Node = @ptrCast(@alignCast(ePtr));
        if (elemNode.* == .element) {
            const element = elemNode.element;
            const newAttr = global_allocator.create(Attr) catch return null;
            newAttr.* = Attr{ .name = name[0..name_len], .value = value[0..value_len], .parentElement = elemNode };
            const newAttrNode = global_allocator.create(Node) catch {
                global_allocator.destroy(newAttr);
                return null;
            };
            newAttrNode.* = Node{ .attribute = newAttr };
            element.setAttribute(elemNode, newAttr) catch {
                global_allocator.destroy(newAttrNode);
                global_allocator.destroy(newAttr);
                return null;
            };
            return newAttrNode;
        }
    }
    return null;
}

pub export fn attr_get(elem: ?*anyopaque, name: [*c]const u8, name_len: usize) ?*Node {
    if (elem) |ePtr| {
        const elemNode: *Node = @ptrCast(@alignCast(ePtr));
        if (elemNode.* == .element) {
            const element = elemNode.element;
            const nameSlice = name[0..name_len];
            if (element.getAttribute(nameSlice)) |attr| {
                const attrNode = global_allocator.create(Node) catch return null;
                attrNode.* = Node{ .attribute = attr };
                return attrNode;
            }
        }
    }
    return null;
}

pub export fn attr_has(elem: ?*anyopaque, name: [*c]const u8, name_len: usize) u32 {
    if (elem) |ePtr| {
        const elemNode: *Node = @ptrCast(@alignCast(ePtr));
        if (elemNode.* == .element) {
            const element = elemNode.element;
            const nameSlice = name[0..name_len];
            for (element.attributes.items, 0..) |item, index| {
                if (item == .attribute and std.mem.eql(u8, item.attribute.name, nameSlice)) {
                    return @as(u32, @intCast(index));
                }
            }
        }
    }
    return std.math.maxInt(u32);  // Equivalent to -1 for u32
}

pub export fn attr_del(elem: ?*anyopaque, name: [*c]const u8, name_len: usize) u32 {
    if (elem) |ePtr| {
        const elemNode: *Node = @ptrCast(@alignCast(ePtr));
        if (elemNode.* == .element) {
            const element = elemNode.element;
            const nameSlice = name[0..name_len];
            element.deleteAttribute(nameSlice, "") catch return 1;  // Assuming empty value for deletion
            return 0;
        }
    }
    return 1;
}

const testing = std.testing;

test "doc_init" {
    const ptr = doc_init();

    try testing.expectEqual(@as(u8, @intFromEnum(NodeType.document)), node_type(ptr));
    try testing.expectEqual(@as(i32, 0), node_free(ptr));
}

test "elem_init" {
  var tag = "a";
  const ptr = elem_init(@as([*c]const u8, &tag[0]), tag.len);

  try testing.expectEqual(@as(u8, @intFromEnum(NodeType.element)), node_type(ptr));
  try testing.expectEqual(@as(i32, 0), node_free(ptr));
}

test "attr_init" {
    const attrPtr = attr_init("testName", 8, "testValue", 9);
    try testing.expect(attrPtr != null);
    try testing.expectEqual(@as(u8, @intFromEnum(NodeType.attribute)), node_type(attrPtr));
    _ = node_free(attrPtr);
}

test "attr_get" {
    const elemPtr = elem_init("div", 3);
    _ = attr_init("class", 5, "container", 9);
    _ = attr_set(elemPtr, "class", 5, "container", 9);
    const gottenAttr = attr_get(elemPtr, "class", 5);
    try testing.expect(gottenAttr != null);
    try testing.expectEqualStrings("container", gottenAttr.?.attribute.value);
    _ = node_free(elemPtr);
    _ = node_free(gottenAttr);
}

test "attr_set" {
    const elemPtr = elem_init("div", 3);
    const setAttr = attr_set(elemPtr, "id", 2, "main", 4);
    try testing.expect(setAttr != null);
    const gottenAttr = attr_get(elemPtr, "id", 2);
    try testing.expectEqualStrings("main", gottenAttr.?.attribute.value);
    _ = node_free(elemPtr);
   _ =  node_free(setAttr);
}

test "attr_has" {
    const elemPtr = elem_init("div", 3);
    _ = attr_set(elemPtr, "data", 4, "info", 4);
    const hasAttr = attr_has(elemPtr, "data", 4);
    try testing.expectEqual(@as(u32, 0), hasAttr);
    const noAttr = attr_has(elemPtr, "nonexistent", 11);
    try testing.expectEqual(std.math.maxInt(u32), noAttr);
    _ = node_free(elemPtr);
}

test "attr_del" {
    // todo
}
