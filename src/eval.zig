// XPath Evaluator
const std = @import("std");
const dom = @import("dom.zig");
const xpath = @import("xpath.zig");

const Allocator = std.mem.Allocator;
const NodeType = dom.NodeType;
const AstNode = xpath.AstNode;
const AstNodeType = xpath.AstNodeType;
const XPathParser = xpath.XPathParser;

pub const XPathError = error{
    InvalidNodeType,
    OutOfMemory,
};

pub const StringPool = struct {
    strings: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) StringPool {
        return .{ .strings = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *StringPool) void {
        for (self.strings.items) |s| {
            self.strings.allocator.free(s);
        }
        self.strings.deinit();
    }

    pub fn add(self: *StringPool, str: []const u8) !u32 {
        const id: u32 = @intCast(self.strings.items.len);
        const duped = try self.strings.allocator.dupe(u8, str);
        try self.strings.append(duped);
        return id;
    }

    pub fn get(self: *const StringPool, id: u32) ?[]const u8 {
        if (id >= self.strings.items.len) return null;
        return self.strings.items[id];
    }
};

pub const XPathEvaluator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) XPathEvaluator {
        return XPathEvaluator{ .allocator = allocator };
    }

    pub fn evaluate(self: *XPathEvaluator, dom_ptr: *const dom.DOM, pool: *const StringPool, context_id: u32, ast: *const AstNode) !std.ArrayList(u32) {
        var nodes = std.ArrayList(u32).init(self.allocator);
        errdefer nodes.deinit();

        if (dom_ptr.nodeType(context_id) == .document) {
            var current = dom_ptr.firstChild(context_id);
            while (current != dom.None) : (current = dom_ptr.next(current)) {
                if (dom_ptr.nodeType(current) == .element) {
                    try self.evaluateNode(dom_ptr, pool, current, ast, &nodes);
                }
            }
        } else {
            try self.evaluateNode(dom_ptr, pool, context_id, ast, &nodes);
        }

        return nodes;
    }

    // Explicitly declare the error set to break the inference cycle
    fn evaluateNode(self: *XPathEvaluator, dom_ptr: *const dom.DOM, pool: *const StringPool, node_id: u32, ast: *const AstNode, result: *std.ArrayList(u32)) XPathError!void {
        if (ast.type != .Element) return;

        const node_type = dom_ptr.nodeType(node_id);
        if (node_type != .element) return;

        try self.evaluateElement(dom_ptr, pool, node_id, ast, result);
    }

    // Explicitly declare the error set to break the inference cycle
    fn evaluateElement(self: *XPathEvaluator, dom_ptr: *const dom.DOM, pool: *const StringPool, elem_id: u32, ast: *const AstNode, result: *std.ArrayList(u32)) XPathError!void {
        if (ast.name) |name| {
            const tag_u32 = dom_ptr.tagName(elem_id);
            const tag_str = pool.get(tag_u32) orelse return;
            if (!std.mem.eql(u8, tag_str, name)) {
                return;
            }
        }

        if (ast.predicate) |pred| {
            if (!try self.evaluatePredicate(dom_ptr, pool, elem_id, pred)) {
                return;
            }
        }

        if (ast.children.items.len == 0) {
            try result.append(elem_id);
            return;
        }

        if (ast.children.items.len > 0) {
            var current = dom_ptr.firstChild(elem_id);
            while (current != dom.None) : (current = dom_ptr.next(current)) {
                try self.evaluateNode(dom_ptr, pool, current, ast.children.items[0], result);
            }
        }
    }

    fn evaluatePredicate(_: *XPathEvaluator, dom_ptr: *const dom.DOM, pool: *const StringPool, elem_id: u32, pred: *const AstNode) !bool {
        if (pred.type != .Predicate) return false;

        const attr_name = pred.attribute orelse return false;
        const expected_value = pred.value orelse return false;

        var current = dom_ptr.firstAttr(elem_id);
        while (current != dom.None) {
            // Check if this is actually an attribute node before calling attrName
            if (dom_ptr.nodeType(current) != .attribute) {
                current = dom_ptr.next(current);
                continue;
            }

            const name_u32 = dom_ptr.attrName(current);
            const name_str = pool.get(name_u32) orelse {
                current = dom_ptr.next(current);
                continue;
            };
            if (std.mem.eql(u8, name_str, attr_name)) {
                const value_u32 = dom_ptr.attrValue(current);
                const value_str = pool.get(value_u32) orelse return false;
                return std.mem.eql(u8, value_str, expected_value);
            }
            current = dom_ptr.next(current);
        }
        return false;
    }
};

// Example usage
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create string pool
    var pool = StringPool.init(allocator);
    defer pool.deinit();

    // Create builder
    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    const root_tag = try pool.add("root");
    const root_id = try builder.createElement(root_tag);
    try builder.appendChild(doc_id, root_id);

    const child_tag = try pool.add("child");
    const child_id = try builder.createElement(child_tag);
    const attr_name_id = try pool.add("attr");
    const attr_value_id = try pool.add("value");
    try builder.setAttribute(child_id, attr_name_id, attr_value_id);
    try builder.appendChild(root_id, child_id);

    const grandchild_tag = try pool.add("grandchild");
    const grandchild_id = try builder.createElement(grandchild_tag);
    try builder.appendChild(child_id, grandchild_id);

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    // Parse XPath
    const xpath_str = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    // Evaluate XPath
    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    // Print results
    std.debug.print("Found {} matching nodes:\n", .{result.items.len});
    for (result.items) |node_id| {
        const tag_u32 = dom_inst.tagName(node_id);
        const tag_str = pool.get(tag_u32).?;
        std.debug.print("{s}\n", .{tag_str});
    }
}

const testing = std.testing;

test "XPathEvaluator: simple path evaluation" {
    const allocator = testing.allocator;

    var pool = StringPool.init(allocator);
    defer pool.deinit();

    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    const root_tag = try pool.add("root");
    const root_id = try builder.createElement(root_tag);
    try builder.appendChild(doc_id, root_id);

    const child_tag = try pool.add("child");
    const child_id = try builder.createElement(child_tag);
    try builder.appendChild(root_id, child_id);

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    const xpath_str = "/root/child";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);
    const found_tag = pool.get(dom_inst.tagName(result.items[0])).?;
    try testing.expectEqualStrings("child", found_tag);
}

test "XPathEvaluator: path with predicate" {
    const allocator = testing.allocator;

    var pool = StringPool.init(allocator);
    defer pool.deinit();

    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    const root_tag = try pool.add("root");
    const root_id = try builder.createElement(root_tag);
    try builder.appendChild(doc_id, root_id);

    const child1_tag = try pool.add("child");
    const child1_id = try builder.createElement(child1_tag);
    const attr_name_id = try pool.add("attr");
    const attr_value_id = try pool.add("value");
    try builder.setAttribute(child1_id, attr_name_id, attr_value_id);
    try builder.appendChild(root_id, child1_id);

    const child2_tag = try pool.add("child");
    const child2_id = try builder.createElement(child2_tag);
    const wrong_value_id = try pool.add("wrong");
    try builder.setAttribute(child2_id, attr_name_id, wrong_value_id);
    try builder.appendChild(root_id, child2_id);

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);
    const found_tag = pool.get(dom_inst.tagName(result.items[0])).?;
    try testing.expectEqualStrings("child", found_tag);
    const found_attr_value_u32 = blk: {
        var current = dom_inst.firstAttr(result.items[0]);
        while (current != dom.None) : (current = dom_inst.next(current)) {
            const name_u32 = dom_inst.attrName(current);
            const name_str = pool.get(name_u32).?;
            if (std.mem.eql(u8, name_str, "attr")) {
                break :blk dom_inst.attrValue(current);
            }
        }
        unreachable;
    };
    const found_attr_value = pool.get(found_attr_value_u32).?;
    try testing.expectEqualStrings("value", found_attr_value);
}

test "XPathEvaluator: complex path" {
    const allocator = testing.allocator;

    var pool = StringPool.init(allocator);
    defer pool.deinit();

    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    const root_tag = try pool.add("root");
    const root_id = try builder.createElement(root_tag);
    try builder.appendChild(doc_id, root_id);

    const child_tag = try pool.add("child");
    const child_id = try builder.createElement(child_tag);
    const attr_name_id = try pool.add("attr");
    const attr_value_id = try pool.add("value");
    try builder.setAttribute(child_id, attr_name_id, attr_value_id);
    try builder.appendChild(root_id, child_id);

    const grandchild_tag = try pool.add("grandchild");
    const grandchild_id = try builder.createElement(grandchild_tag);
    try builder.appendChild(child_id, grandchild_id);

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    const xpath_str = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);
    const found_tag = pool.get(dom_inst.tagName(result.items[0])).?;
    try testing.expectEqualStrings("grandchild", found_tag);
}

test "XPathEvaluator: no matching nodes" {
    const allocator = testing.allocator;

    var pool = StringPool.init(allocator);
    defer pool.deinit();

    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    const root_tag = try pool.add("root");
    const root_id = try builder.createElement(root_tag);
    try builder.appendChild(doc_id, root_id);

    const child_tag = try pool.add("child");
    const child_id = try builder.createElement(child_tag);
    const attr_name_id = try pool.add("attr");
    const wrong_value_id = try pool.add("wrong");
    try builder.setAttribute(child_id, attr_name_id, wrong_value_id);
    try builder.appendChild(root_id, child_id);

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 0), result.items.len);
}

test "XPathEvaluator: empty document" {
    const allocator = testing.allocator;

    var pool = StringPool.init(allocator);
    defer pool.deinit();

    var builder = try dom.Builder.init(allocator);
    defer builder.deinit();

    const doc_id = try builder.createDocument();

    var dom_inst = try builder.build();
    defer dom_inst.deinit();

    const xpath_str = "/root";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&dom_inst, &pool, doc_id, ast);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 0), result.items.len);
}
