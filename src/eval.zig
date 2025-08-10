const std = @import("std");
const dom = @import("dom.zig");
const xpath = @import("xpath.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const NodeType = dom.NodeType;
const AstNode = xpath.AstNode;
const AstNodeType = xpath.AstNodeType;
const XPathParser = xpath.XPathParser;

pub const XPathError = error{
    InvalidNodeType,
    OutOfMemory,
};

pub const XPathResult = struct {
    nodes: std.ArrayList(*Node),

    pub fn init(allocator: Allocator) XPathResult {
        return XPathResult{
            .nodes = std.ArrayList(*Node).init(allocator),
        };
    }

    pub fn deinit(self: *XPathResult) void {
        self.nodes.deinit();
    }

    pub fn append(self: *XPathResult, node: *Node) !void {
        try self.nodes.append(node);
    }
};

pub const XPathEvaluator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) XPathEvaluator {
        return XPathEvaluator{ .allocator = allocator };
    }

    pub fn evaluate(self: *XPathEvaluator, doc: *Node, ast: *AstNode) !XPathResult {
        var result = XPathResult.init(self.allocator);
        errdefer result.deinit();

        // Start evaluation from the document node
        try self.evaluateNode(doc, ast, &result);
        return result;
    }

    fn evaluateNode(self: *XPathEvaluator, node: *Node, ast: *AstNode, result: *XPathResult) XPathError!void {
        if (ast.type != .Element) return;

        // Check if the current node can contain children
        const node_type = node.archetype();
        if (node_type == .document or node_type == .element) {
            switch (node.*) {
                .document => try self.evaluateDocument(node, ast, result),
                .element => try self.evaluateElement(node, ast, result),
                else => return,
            }
        }
    }

    fn evaluateDocument(self: *XPathEvaluator, doc_node: *Node, ast: *AstNode, result: *XPathResult) XPathError!void {
        // Document node: process all children
        const children_list = doc_node.children();
        for (children_list.values()) |child| {
            try self.evaluateNode(child, ast, result);
        }
    }

    fn evaluateElement(self: *XPathEvaluator, elem_node: *Node, ast: *AstNode, result: *XPathResult) XPathError!void {
        // Check if element matches the AST node name
        if (ast.name) |name| {
            const tag_name = elem_node.tagName();
            if (!std.mem.eql(u8, tag_name, name)) {
                return;
            }
        }

        // Check predicate if present
        if (ast.predicate) |pred| {
            if (!try self.evaluatePredicate(elem_node, pred)) {
                return;
            }
        }

        // If this is the last node in the path, add to results
        if (ast.children.items.len == 0) {
            try result.append(elem_node);
            return;
        }

        // Process children with the next AST node
        if (ast.children.items.len > 0) {
            const children_list = elem_node.children();
            for (children_list.values()) |child| {
                try self.evaluateNode(child, ast.children.items[0], result);
            }
        }
    }

    fn evaluatePredicate(_: *XPathEvaluator, elem_node: *Node, pred: *AstNode) XPathError!bool {
        if (pred.type != .Predicate) return false;

        if (pred.attribute) |attr_name| {
            if (pred.value) |expected_value| {
                // Convert attr_name to null-terminated string for getAttribute
                var attr_name_z = std.heap.page_allocator.allocSentinel(u8, attr_name.len, 0) catch return false;
                defer std.heap.page_allocator.free(attr_name_z);
                @memcpy(attr_name_z[0..attr_name.len], attr_name);

                if (elem_node.getAttribute(attr_name_z)) |attr_value| {
                    return std.mem.eql(u8, attr_value, expected_value);
                }
            }
        }
        return false;
    }
};

// Example usage and test
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create a sample XML document
    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    // Create root element
    const root = try Node.Elem(allocator, "root");
    try doc.append(root);

    // Create child element with attribute
    const child = try Node.Elem(allocator, "child");
    try child.setAttribute("attr", "value");
    try root.append(child);

    // Create grandchild element
    const grandchild = try Node.Elem(allocator, "grandchild");
    try child.append(grandchild);

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
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Print results
    std.debug.print("Found {} matching nodes:\n", .{result.nodes.items.len});
    for (result.nodes.items) |node| {
        var writer = std.io.getStdOut().writer();
        try node.render(writer);
        try writer.print("\n", .{});
    }
}

const testing = std.testing;

test "XPathEvaluator: simple path evaluation" {
    const allocator = testing.allocator;

    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    const root = try Node.Elem(allocator, "root");
    try doc.append(root);

    const child = try Node.Elem(allocator, "child");
    try root.append(child);

    // Parse and evaluate XPath
    const xpath_str = "/root/child";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Verify results
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].archetype());
    try testing.expectEqualStrings("child", result.nodes.items[0].tagName());
}

test "XPathEvaluator: path with predicate" {
    const allocator = testing.allocator;

    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    const root = try Node.Elem(allocator, "root");
    try doc.append(root);

    // Create first child with matching attribute
    const child1 = try Node.Elem(allocator, "child");
    try child1.setAttribute("attr", "value");
    try root.append(child1);

    // Create second child with different attribute
    const child2 = try Node.Elem(allocator, "child");
    try child2.setAttribute("attr", "wrong");
    try root.append(child2);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Verify results - should only match the first child
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].archetype());
    try testing.expectEqualStrings("child", result.nodes.items[0].tagName());
    try testing.expectEqualStrings("value", result.nodes.items[0].getAttribute("attr").?);
}

test "XPathEvaluator: complex path" {
    const allocator = testing.allocator;

    // Create complex XML document
    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    const root = try Node.Elem(allocator, "root");
    try doc.append(root);

    const child = try Node.Elem(allocator, "child");
    try child.setAttribute("attr", "value");
    try root.append(child);

    const grandchild = try Node.Elem(allocator, "grandchild");
    try child.append(grandchild);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Verify results
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].archetype());
    try testing.expectEqualStrings("grandchild", result.nodes.items[0].tagName());
}

test "XPathEvaluator: no matching nodes" {
    const allocator = testing.allocator;

    // Create XML document
    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    const root = try Node.Elem(allocator, "root");
    try doc.append(root);

    const child = try Node.Elem(allocator, "child");
    try child.setAttribute("attr", "wrong");
    try root.append(child);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Verify no matches
    try testing.expectEqual(@as(usize, 0), result.nodes.items.len);
}

test "XPathEvaluator: empty document" {
    const allocator = testing.allocator;

    // Create empty document
    var doc = try Node.Doc(allocator);
    defer doc.destroy();

    // Parse and evaluate XPath
    const xpath_str = "/root";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(doc, ast);
    defer result.deinit();

    // Verify no matches
    try testing.expectEqual(@as(usize, 0), result.nodes.items.len);
}
