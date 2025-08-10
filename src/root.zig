const std = @import("std");
const dom = @import("dom.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const Element = dom.Element;
const Document = dom.Document;
const NodeType = dom.NodeType;
const NodeList = dom.NodeList;
const NamedNodeMap = dom.NamedNodeMap;

const alloc = std.heap.page_allocator;

// FFI for XML

inline fn getNode(p: ?*anyopaque) ?*Node {
    if (p == null) return null;
    return @alignCast(@ptrCast(p));
}

pub export fn alloc_elem(tag: [*c]const u8) callconv(.C) ?*anyopaque {
    const slice = std.mem.span(tag);
    const node = Node.Elem(alloc, slice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_attr(name: [*c]const u8, value: [*c]const u8) callconv(.C) ?*anyopaque {
    const nslice = std.mem.span(name);
    const vslice = std.mem.span(value);
    const node = Node.Attr(alloc, nslice, vslice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_text(content: [*c]const u8) callconv(.C) ?*anyopaque {
    const slice = std.mem.span(content);
    const node = Node.Text(alloc, slice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_cdata(content: [*c]const u8) callconv(.C) ?*anyopaque {
    const slice = std.mem.span(content);
    const node = Node.CData(alloc, slice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_comment(content: [*c]const u8) callconv(.C) ?*anyopaque {
    const slice = std.mem.span(content);
    const node = Node.Comment(alloc, slice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_procinst(content: [*c]const u8) callconv(.C) ?*anyopaque {
    const slice = std.mem.span(content);
    const node = Node.ProcInst(alloc, slice) catch return null;
    return @ptrCast(node);
}

pub export fn alloc_doc() callconv(.C) ?*anyopaque {
    const node = Node.Doc(alloc) catch return null;
    return @ptrCast(node);
}

pub export fn node_free(p: ?*anyopaque) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    node.destroy();
    return 0;
}

pub export fn node_type(p: ?*anyopaque) callconv(.C) u8 {
    const node = getNode(p) orelse return 0;
    return @intFromEnum(node.archetype());
}

pub export fn node_parent(p: ?*anyopaque) callconv(.C) ?*anyopaque {
    const node = getNode(p) orelse return null;
    const par = node.parent() orelse return null;
    return @ptrCast(par);
}

pub export fn node_set_parent(p: ?*anyopaque, par_p: ?*anyopaque) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    const par = getNode(par_p);
    node.setParent(par);
    return 0;
}

pub export fn inode_children(p: ?*anyopaque) callconv(.C) ?*anyopaque {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .element and node.archetype() != .document) return null;
    return @ptrCast(node.children());
}

pub export fn inode_count(p: ?*anyopaque) callconv(.C) i64 {
    const node = getNode(p) orelse return -1;
    if (node.archetype() != .element and node.archetype() != .document) return -1;
    return @intCast(node.count());
}

pub export fn inode_append(p: ?*anyopaque, child_p: ?*anyopaque) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    const child = getNode(child_p) orelse return -1;
    if (node.archetype() != .element and node.archetype() != .document) return -1;
    node.append(child) catch return -1;
    return 0;
}

pub export fn inode_prepend(p: ?*anyopaque, child_p: ?*anyopaque) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    const child = getNode(child_p) orelse return -1;
    if (node.archetype() != .element and node.archetype() != .document) return -1;
    node.prepend(child) catch return -1;
    return 0;
}

pub export fn elem_tag(p: ?*anyopaque) callconv(.C) [*c]const u8 {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .element) return null;
    return node.tagName().ptr;
}

pub export fn elem_attrs(p: ?*anyopaque) callconv(.C) ?*anyopaque {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .element) return null;
    return @ptrCast(node.attributes());
}

pub export fn elem_get_attr(p: ?*anyopaque, name: [*c]const u8) callconv(.C) [*c]const u8 {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .element) return null;
    const slice = std.mem.span(name);
    const val = node.getAttribute(slice) orelse return null;
    return val.ptr;
}

pub export fn elem_set_attr(p: ?*anyopaque, name: [*c]const u8, value: [*c]const u8) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    if (node.archetype() != .element) return -1;
    const nslice = std.mem.span(name);
    const vslice = std.mem.span(value);
    node.setAttribute(nslice, vslice) catch return -1;
    return 0;
}

pub export fn elem_remove_attr(p: ?*anyopaque, name: [*c]const u8) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    if (node.archetype() != .element) return -1;
    // Note: Original code has removeAttribute as TODO, so implement based on attributes
    const slice = std.mem.span(name);
    node.attributes().removeNamedItem(slice);
    return 0;
}

pub export fn attr_name(p: ?*anyopaque) callconv(.C) [*c]const u8 {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .attribute) return null;
    return node.getName().ptr;
}

pub export fn attr_value(p: ?*anyopaque) callconv(.C) [*c]const u8 {
    const node = getNode(p) orelse return null;
    if (node.archetype() != .attribute) return null;
    return node.getValue().ptr;
}

pub export fn attr_set_value(p: ?*anyopaque, value: [*c]const u8) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    if (node.archetype() != .attribute) return -1;
    const slice = std.mem.span(value);
    node.setValue(slice) catch return -1;
    return 0;
}

pub export fn content_get(p: ?*anyopaque) callconv(.C) [*c]const u8 {
    const node = getNode(p) orelse return null;
    const typ = node.archetype();
    if (typ != .text and typ != .cdata and typ != .comment and typ != .proc_inst) return null;
    return node.getContent().ptr;
}

pub export fn content_set(p: ?*anyopaque, content: [*c]const u8) callconv(.C) i32 {
    const node = getNode(p) orelse return -1;
    const typ = node.archetype();
    if (typ != .text and typ != .cdata and typ != .comment and typ != .proc_inst) return -1;
    const slice = std.mem.span(content);
    node.setContent(slice) catch return -1;
    return 0;
}

pub export fn map_length(m_p: ?*anyopaque) callconv(.C) i32 {
    const map:*NamedNodeMap = @alignCast(@ptrCast(m_p orelse return -1));
    return @intCast(map.length());
}

pub export fn map_item(m_p: ?*anyopaque, index: i32) callconv(.C) ?*anyopaque {
    const map:*NamedNodeMap = @alignCast(@ptrCast(m_p orelse return null));
    if (index < 0) return null;
    return @ptrCast(map.item(@intCast(index)) orelse return null);
}

pub export fn map_get(m_p: ?*anyopaque, name: [*c]const u8) callconv(.C) ?*anyopaque {
    const map:*NamedNodeMap = @alignCast(@ptrCast(m_p orelse return null));
    const slice = std.mem.span(name);
    return @ptrCast(map.getNamedItem(slice) orelse return null);
}

pub export fn map_set(m_p: ?*anyopaque, item_p: ?*anyopaque) callconv(.C) i32 {
    const map:*NamedNodeMap = @alignCast(@ptrCast(m_p orelse return -1));
    const item = getNode(item_p) orelse return -1;
    map.setNamedItem(item) catch return -1;
    return 0;
}

pub export fn map_remove(m_p: ?*anyopaque, name: [*c]const u8) callconv(.C) i32 {
    const map:*NamedNodeMap = @alignCast(@ptrCast(m_p orelse return -1));
    const slice = std.mem.span(name);
    map.removeNamedItem(slice);
    return 0;
}

pub export fn list_length(l_p: ?*anyopaque) callconv(.C) i32 {
    const list:*NodeList = @alignCast(@ptrCast(l_p orelse return -1));
    return @intCast(list.length());
}

pub export fn list_item(l_p: ?*anyopaque, index: i32) callconv(.C) ?*anyopaque {
    const list:*NodeList = @alignCast(@ptrCast(l_p orelse return null));
    if (index < 0) return null;
    return @ptrCast(list.item(@intCast(index)) orelse return null);
}

pub export fn list_append(l_p: ?*anyopaque, item_p: ?*anyopaque) callconv(.C) i32 {
    const list:*NodeList = @alignCast(@ptrCast(l_p orelse return -1));
    const item = getNode(item_p) orelse return -1;
    list.append(item) catch return -1;
    return 0;
}

pub export fn list_prepend(l_p: ?*anyopaque, item_p: ?*anyopaque) callconv(.C) i32 {
    const list:*NodeList = @alignCast(@ptrCast(l_p orelse return -1));
    const item = getNode(item_p) orelse return -1;
    list.insert(0, item) catch return -1;
    return 0;
}

// FFI for Sax

// Add these imports to the existing ffi.zig file
const xpath_parser = @import("xpath.zig");
const eval = @import("eval.zig");

// Add this function to the existing FFI functions in ffi.zig

pub export fn xpath_eval(xpath_str: [*c]const u8, context_node: ?*anyopaque) callconv(.C) ?*anyopaque {
    const node = getNode(context_node) orelse return null;
    const xpath_slice = std.mem.span(xpath_str);

    // Parse the XPath expression
    var parser = xpath_parser.XPathParser.init(alloc);
    const ast = parser.parse(xpath_slice) catch return null;
    defer {
        ast.deinit(alloc);
        alloc.destroy(ast);
    }

    // Evaluate the XPath against the context node
    var evaluator = eval.XPathEvaluator.init(alloc);
    var result = evaluator.evaluate(node, ast) catch return null;

    // Create a new NodeList to return the results
    const result_list = alloc.create(dom.NodeList) catch {
        result.deinit();
        return null;
    };
    result_list.* = dom.NodeList.init(alloc);

    // Copy the result nodes to the new NodeList
    for (result.nodes.items) |result_node| {
        result_list.append(result_node) catch {
            result.deinit();
            result_list.deinit();
            alloc.destroy(result_list);
            return null;
        };
    }

    // Clean up the XPath result (but not the nodes themselves, as they're owned by the DOM)
    result.deinit();

    return @ptrCast(result_list);
}

// Helper function to free XPath result NodeList
pub export fn xpath_result_free(result_list: ?*anyopaque) callconv(.C) i32 {
    const list: *dom.NodeList = @alignCast(@ptrCast(result_list orelse return -1));

    // Note: We don't call deinit() on the NodeList because that would destroy
    // the nodes themselves, which are owned by the original DOM tree.
    // Instead, we just free the list structure and its internal ArrayList.
    list.list.deinit();
    alloc.destroy(list);
    return 0;
}

// Additional utility function for getting XPath result count
pub export fn xpath_result_length(result_list: ?*anyopaque) callconv(.C) i32 {
    const list: *dom.NodeList = @alignCast(@ptrCast(result_list orelse return -1));
    return @intCast(list.length());
}

// Additional utility function for getting XPath result item
pub export fn xpath_result_item(result_list: ?*anyopaque, index: i32) callconv(.C) ?*anyopaque {
    const list: *dom.NodeList = @alignCast(@ptrCast(result_list orelse return null));
    if (index < 0) return null;
    return @ptrCast(list.item(@intCast(index)) orelse return null);
}

const testing = std.testing;

test "XPath FFI: basic path evaluation" {
    // Create a simple XML structure using FFI functions
    const doc = alloc_doc();
    defer _ = node_free(doc);

    const root = alloc_elem("root");
    const child1 = alloc_elem("child");
    const child2 = alloc_elem("child");

    // Build the structure: <root><child attr="a">A</child><child attr="b">B</child></root>
    _ = inode_append(doc, root);
    _ = inode_append(root, child1);
    _ = inode_append(root, child2);

    // Set attributes
    _ = elem_set_attr(child1, "attr", "a");
    _ = elem_set_attr(child2, "attr", "b");

    // Add text content
    const text1 = alloc_text("A");
    const text2 = alloc_text("B");
    _ = inode_append(child1, text1);
    _ = inode_append(child2, text2);

    // Test XPath evaluation
    const xpath_str = "/root/child[@attr=\"a\"]";
    const result = xpath_eval(xpath_str, doc);
    defer _ = xpath_result_free(result);

    // Check results
    const length = xpath_result_length(result);
    try testing.expectEqual(@as(i32, 1), length);

    const first_node = xpath_result_item(result, 0);
    try testing.expect(first_node != null);

    // Verify it's the correct element
    const tag_name = elem_tag(first_node);
    try testing.expectEqualStrings("child", std.mem.span(tag_name));
}

test "XPath FFI: multiple matches" {
    // Create XML structure with multiple matching elements
    const doc = alloc_doc();
    defer _ = node_free(doc);

    const root = alloc_elem("root");
    _ = inode_append(doc, root);

    // Create multiple child elements
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        const child = alloc_elem("child");
        _ = inode_append(root, child);
    }

    // Test XPath that matches all children
    const xpath_str = "/root/child";
    const result = xpath_eval(xpath_str, doc);
    defer _ = xpath_result_free(result);

    // Check results
    const length = xpath_result_length(result);
    try testing.expectEqual(@as(i32, 3), length);

    // Verify all results are 'child' elements
    var j: i32 = 0;
    while (j < length) : (j += 1) {
        const node = xpath_result_item(result, j);
        try testing.expect(node != null);
        const tag_name = elem_tag(node);
        try testing.expectEqualStrings("child", std.mem.span(tag_name));
    }
}

test "XPath FFI: no matches" {
    const doc = alloc_doc();
    defer _ = node_free(doc);

    const root = alloc_elem("root");
    _ = inode_append(doc, root);

    // Test XPath that doesn't match anything
    const xpath_str = "/root/nonexistent";
    const result = xpath_eval(xpath_str, doc);
    defer _ = xpath_result_free(result);

    // Check results
    const length = xpath_result_length(result);
    try testing.expectEqual(@as(i32, 0), length);

    // Verify getting item returns null
    const node = xpath_result_item(result, 0);
    try testing.expectEqual(@as(?*anyopaque, null), node);
}
