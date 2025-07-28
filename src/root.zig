const std = @import("std");
const dom = @import("./dom.zig");
const sax = @import("./sax.zig");
const xpath = @import("./xpath.zig");
const eval = @import("./eval.zig");
const xml = @import("./parse.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const Element = dom.Element;
const Document = dom.Document;
const Text = dom.Text;
const Attr = dom.Attr;
const NodeType = dom.NodeType;

const DOMParser = xml.DomParser;

const SaxParser = sax.SaxParser;
const SaxEvent = sax.SaxEvent;

const XPathParser = xpath.XPathParser;

const XPathEvaluator = eval.XPathEvaluator;
const XPathResult = eval.XPathResult;
const XPathError = eval.XPathError;

const alloc = std.heap.page_allocator;

pub export fn doc_init() ?*anyopaque {
    const node = alloc.create(Node) catch return null;
    const doc = alloc.create(Document) catch {
      alloc.destroy(node);
      return null;
    };
    doc.* = Document.init(alloc);
    node.* = Node{ .document = doc };
    return node;
}

pub export fn elem_init(buf: [*c]const u8, len: usize) ?*anyopaque {
    const node = alloc.create(Node) catch return null;
    const elem = alloc.create(Element) catch {
      alloc.destroy(node);
      return null;
    };
    elem.* = Element.init(alloc, buf[0..len]);
    node.* = Node{ .element = elem };
    return node;
}

pub export fn node_free(ptr: ?*anyopaque) i32 {
  if (ptr == null) return 0;
  const node:*Node = @ptrCast(@alignCast(ptr));
  node.deinit();
  alloc.destroy(node);
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
    const c_str = alloc.dupeZ(u8, n.element.tagName) catch return null;
    return @as([*c]u8, c_str.ptr);
}

// Returns new attribute node
pub export fn attr_init(name: [*c]const u8, name_len: usize, value: [*c]const u8, value_len: usize) ?*Node {
  const node = alloc.create(Node) catch return null;
  const attr = alloc.create(Attr) catch {
    alloc.destroy(node);
    return null;
  };
  attr.* = Attr{
      .name = alloc.dupe(u8, name[0..name_len:0]) catch {  // Ensure null-terminated if needed
          alloc.destroy(attr);
          alloc.destroy(node);
          return null;
      },
      .value = alloc.dupe(u8, value[0..value_len]) catch {
          // global_allocator.destroy(attr.name.ptr);  // Clean up if name was allocated
          alloc.destroy(attr);
          alloc.destroy(node);
          return null;
      },
  };
  node.* = Node{ .attribute = attr };
  return node;
}

// Returns name from attribute node
pub export fn attr_name(attr: *anyopaque) [*c]u8 {
    const n: *Node = @ptrCast(@alignCast(attr));
    if (n.* == .attribute) {
      const c_str = alloc.dupeZ(u8, n.attribute.name) catch return null;
      return @as([*c]u8, c_str.ptr);
    }
    return null;
}

// Returns value from attribute node
pub export fn attr_val(node: *anyopaque) [*c]u8 {
    const n: *Node = @ptrCast(@alignCast(node));
    if (n.* == .attribute) {
      const c_str = alloc.dupeZ(u8, n.attribute.value) catch return null;
      return @as([*c]u8, c_str.ptr);
    }
    return null;
}

// Change to value of a attribute node
pub export fn attr_set(attr: *anyopaque, buf: [*c]const u8, len: usize) u32 {
    // if (attrNodePtr == null) @panic("attrNodePtr is null");  // Handle invalid input
    const attrNode: *Node = @ptrCast(@alignCast(attr));
    if (attrNode.* != .attribute) return 1;  // Not an attribute node
    const attribute = attrNode.attribute;

    // Duplicate the new value
    const newValueDupe = alloc.dupe(u8, buf[0..len]) catch return 1;

    // Free the old value if it exists
    alloc.free(attribute.value);

    attribute.value = newValueDupe;
    return 0;  // Success
}

pub export fn attr_add(elem: ?*anyopaque, attr: ?*anyopaque) u8 {
    const elemNode: *Node = @ptrCast(@alignCast(elem));
    const attrNode: *Node = @ptrCast(@alignCast(attr));
    if (elemNode.* != .element or attrNode.* != .attribute) return 1;
    elemNode.element.setAttributeNode(elemNode, attrNode) catch return 1; // Use setAttributeNode
    return 0;
}

pub export fn attr_get(elem: *anyopaque, name: [*c]const u8, len: usize) ?*Node {
    const elemNode: *Node = @ptrCast(@alignCast(elem));
    if (elemNode.* != .element) return null;
    return elemNode.element.getAttributeNode(name[0..len]); // Use getAttributeNode
}

pub export fn attr_del(elem: *anyopaque, name: [*c]const u8, name_len: usize) u32 {
    const elemNode: *Node = @ptrCast(@alignCast(elem));
    if (elemNode.* != .element) return 1;
    elemNode.element.removeAttribute(name[0..name_len]) catch return 1; // Use removeAttribute
    return 0;
}

pub export fn parse(text: [*:0]const u8) ?*anyopaque {
    const xml_slice = std.mem.span(text);
    const parser = DOMParser.init(alloc) catch return null;
    const node = parser.parse(xml_slice) catch return null;
    return node;
}

const testing = std.testing;

fn checkNodeType(ptr: ?*anyopaque, expected: NodeType) !void {
  try testing.expectEqual(@as(u8, @intFromEnum(expected)), node_type(ptr));
}

test "doc_init" {
    const ptr = doc_init();
    try checkNodeType(ptr, NodeType.document);
    _ = node_free(ptr);
}

test "elem_init" {
  const ptr = elem_init("a", 1);
  try checkNodeType(ptr, NodeType.element);
  _ = node_free(ptr);
}

test "attr_init" {
    const attr = attr_init("id", 2, "1", 1);
    try testing.expect(attr != null);
    try checkNodeType(attr, NodeType.attribute);
    _ = node_free(attr);
}

test "attr_name" {
    const attr = attr_init("id", 2, "1", 1);
    try testing.expect(attr != null);
    const name = attr_name(@as(*anyopaque, @ptrCast(attr.?)));
    try testing.expect(name != null);
    const nameStr = std.mem.span(name);
    try testing.expectEqualStrings("id", nameStr);
    _ = node_free(attr);
    alloc.free(nameStr);
}

test "attr_val" {
    const attr = attr_init("id", 2, "1", 1);
    try testing.expect(attr != null);
    const value = attr_val(@as(*anyopaque, @ptrCast(attr.?)));
    try testing.expect(value != null);
    const valueStr = std.mem.span(value);
    try testing.expectEqualStrings("1", valueStr);
    _ = node_free(attr);
    alloc.free(valueStr);
}

test "attr_set" {
    const attr = attr_init("a", 1, "1", 1);
    const status = attr_set(@ptrCast(attr), "2", 1);
    try testing.expect(status == 0);
    const val = attr_val(@ptrCast(attr));
    try testing.expectEqualStrings("2", std.mem.span(val));
   _ = node_free(attr);
}

test "attr_add" {
  const elem = elem_init("a", 1);
  const attr = attr_init("id", 2, "1", 2);
  _ = attr_add(elem, attr);
}

test "attr_get" {
    // const elemPtr = elem_init("div", 3);
    // _ = attr_init("class", 5, "container", 9);
    // // First, get the attribute node, then set it
    // const attrNode = attr_get(elemPtr, "class", 5);
    // if (attrNode != null) {
    //     _ = attr_set(@ptrCast(attrNode), "container", 9);
    // }
    // const gottenAttr = attr_get(elemPtr, "class", 5);
    // try testing.expect(gottenAttr != null);
    // try testing.expectEqualStrings("main", gottenAttr.?.attribute.value);
    // _ = node_free(elemPtr);
    // _ = node_free(gottenAttr);
}

// test "attr_has" {
    // const elemPtr = elem_init("div", 3);
    // const attrNodeData = attr_get(elemPtr, "data", 4);
    // try testing.expectEqual(null, attrNodeData);
    // _ = attr_set(@ptrCast(attrNodeData), "info", 4);
    // const hasAttr = attr_has(elemPtr, "data", 4);
    // try testing.expectEqual(@as(u32, 0), hasAttr);
    // const noAttr = attr_has(elemPtr, "nonexistent", 11);
    // try testing.expectEqual(std.math.maxInt(u32), noAttr);
    // _ = node_free(elemPtr);
// }

test "attr_del" {
    // const elemPtr = elem_init("div", 3);
    // try testing.expect(elemPtr != null);
    // _ = attr_add(elemPtr, "toDelete", 9, "value", 5);  // Add an attribute to delete
    // const hasBefore = attr_has(elemPtr, "toDelete", 9);
    // try testing.expect(hasBefore != std.math.maxInt(u32));  // Ensure it exists
    // const deleteResult = attr_del(elemPtr, "toDelete", 9);
    // try testing.expectEqual(@as(u32, 0), deleteResult);  // Expect success
    // const hasAfter = attr_has(elemPtr, "toDelete", 9);
    // try testing.expectEqual(std.math.maxInt(u32), hasAfter);  // Ensure it's deleted after proper deletion
    // _ = node_free(elemPtr);
}
