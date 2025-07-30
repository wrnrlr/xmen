const std = @import("std");
const dom = @import("dom.zig");
const xpath = @import("xpath.zig");

const Allocator = std.mem.Allocator;
const Node = dom.Node;
const Element = dom.Element;
const Document = dom.Document;
const NodeType = dom.NodeType;
const AstNode = xpath.AstNode;
const AstNodeType = xpath.AstNodeType;
const XPathParser = xpath.XPathParser;
const Attr = dom.Attr;

pub const XPathError = error{
    InvalidNodeType,
    OutOfMemory,
};

pub const XPathResult = struct {
    nodes: std.ArrayList(Node),

    pub fn init(allocator: Allocator) XPathResult {
        return XPathResult{
            .nodes = std.ArrayList(Node).init(allocator),
        };
    }

    pub fn deinit(self: *XPathResult) void {
        self.nodes.deinit();
    }

    pub fn append(self: *XPathResult, node: Node) !void {
        try self.nodes.append(node);
    }
};

pub const XPathEvaluator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) XPathEvaluator {
        return XPathEvaluator{ .allocator = allocator };
    }

    pub fn evaluate(self: *XPathEvaluator, doc: *Document, ast: *AstNode) !XPathResult {
        var result = XPathResult.init(self.allocator);
        errdefer result.deinit();

        // Wrap the Document in a Node union
        const doc_node = Node{ .document = doc };
        try self.evaluateNode(doc_node, ast, &result);
        return result;
    }

    fn evaluateNode(self: *XPathEvaluator, node: Node, ast: *AstNode, result: *XPathResult) XPathError!void {
        if (ast.type != .Element) return;

        // Check if the current node matches the AST node
        if (node.getNodeType() == .document or node.getNodeType() == .element) {
            switch (node) {
                .document => |doc| try self.evaluateDocument(doc, ast, result),
                .element => |elem| try self.evaluateElement(elem, ast, result),
                else => return,
            }
        }
    }

    fn evaluateDocument(self: *XPathEvaluator, doc: *Document, ast: *AstNode, result: *XPathResult) XPathError!void {
        // Document node: process all children
        for (doc.children.items) |child| {
            try self.evaluateNode(child.*, ast, result);
        }
    }

    fn evaluateElement(self: *XPathEvaluator, elem: *Element, ast: *AstNode, result: *XPathResult) XPathError!void {
        // Check if element matches the AST node name
        if (ast.name) |name| {
            if (!std.mem.eql(u8, elem.tagName, name)) {
                return;
            }
        }

        // Check predicate if present
        if (ast.predicate) |pred| {
            if (!try self.evaluatePredicate(elem, pred)) {
                return;
            }
        }

        // If this is the last node in the path, add to results
        if (ast.children.items.len == 0) {
            try result.append(Node{ .element = elem });
            return;
        }

        // Process children with the next AST node
        if (ast.children.items.len > 0) {
            for (elem.children.items) |child| {
                try self.evaluateNode(child.*, ast.children.items[0], result);
            }
        }
    }

    fn evaluatePredicate(_: *XPathEvaluator, elem: *Element, pred: *AstNode) XPathError!bool {
        if (pred.type != .Predicate) return false;

        if (pred.attribute) |attr_name| {
            if (pred.value) |expected_value| {
                if (elem.getAttributeNode(attr_name)) |attr_node| {
                    return std.mem.eql(u8, attr_node.attribute.value, expected_value);
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
    var doc = Document{
        .tagName = "document",
        .children = std.ArrayList(*Node).init(allocator),
    };
    defer doc.children.deinit();

    // Use `var` to make elements mutable
    var root = Element.init(allocator, "root");
    var child = Element.init(allocator, "child");
    const attr = try allocator.create(Attr);
    attr.* = Attr.init("attr", "value", null);
    const attr_node = try allocator.create(Node);
    attr_node.* = Node{ .attribute = attr };
    try child.setAttributeNode(&Node{ .element = &child }, attr_node);
    var grandchild = Element.init(allocator, "grandchild");

    // Create mutable Node pointers
    const grandchild_node = try allocator.create(Node);
    grandchild_node.* = Node{ .element = &grandchild };
    const child_parent_node = try allocator.create(Node);
    child_parent_node.* = Node{ .element = &child };
    _ = try child.appendChild(child_parent_node, grandchild_node);
    const root_parent_node = try allocator.create(Node);
    root_parent_node.* = Node{ .element = &root };
    _ = try root.appendChild(root_parent_node, child_parent_node);
    const root_node = try allocator.create(Node);
    root_node.* = Node{ .element = &root };
    _ = try doc.children.append(root_node);

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
    var result = try evaluator.evaluate(&doc, ast);
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

    var doc = Document.init(allocator);
    defer doc.deinit();

    var root = Element.init(allocator, "root");
    var child = Element.init(allocator, "child");

    const child_node = try allocator.create(Node);
    child_node.* = Node{ .element = &child };
    const root_node = try allocator.create(Node);
    root_node.* = Node{ .element = &root };
    _ = try root.appendChild(root_node, child_node); // Use root_node as parent
    try doc.children.append(root_node);

    // Parse and evaluate XPath
    const xpath_str = "/root/child";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&doc, ast);
    defer result.deinit();

    // Verify results
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].getNodeType());
    try testing.expectEqualStrings("child", result.nodes.items[0].element.tagName);
}

test "XPathEvaluator: path with predicate" {
    const allocator = testing.allocator;

    var doc = Document.init(allocator);
    defer doc.deinit();

    var root = Element.init(allocator, "root");
    var child = Element.init(allocator, "child");
    var child2 = Element.init(allocator, "child");

    // Create attribute for child
    const attr = try allocator.create(Attr);
    attr.* = Attr.init("attr", "value", null);
    const attr_node = try allocator.create(Node);
    attr_node.* = Node{ .attribute = attr };
    try child.setAttributeNode(@constCast(&Node{ .element = @constCast(&child) }), attr_node);

    // Create attribute for child2
    const attr2 = try allocator.create(Attr);
    attr2.* = Attr.init("attr", "wrong", null);
    const attr2_node = try allocator.create(Node);
    attr2_node.* = Node{ .attribute = attr2 };
    try child2.setAttributeNode(@constCast(&Node{ .element = @constCast(&child2) }), attr2_node);

    // Build DOM tree
    const child_node = try allocator.create(Node);
    child_node.* = Node{ .element = &child };
    const child2_node = try allocator.create(Node);
    child2_node.* = Node{ .element = &child2 };
    const root_node = try allocator.create(Node);
    root_node.* = Node{ .element = &root };
    _ = try root.appendChild(root_node, child_node);
    _ = try root.appendChild(root_node, child2_node);
    try doc.children.append(root_node);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&doc, ast);
    defer result.deinit();

    // Verify results
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].getNodeType());
    try testing.expectEqualStrings("child", result.nodes.items[0].element.tagName);
    try testing.expectEqualStrings("value", result.nodes.items[0].element.getAttributeNode("attr").?.attribute.value);
}

test "XPathEvaluator: complex path" {
    const allocator = testing.allocator;

    // Create complex XML document
    var doc = Document.init(allocator);
    defer doc.deinit();

    var root = Element.init(allocator, "root");
    defer root.deinit();
    var child = Element.init(allocator, "child");
    defer child.deinit();
    const attr = try allocator.create(Attr);
    attr.* = Attr.init("attr", "value", null);
    const attr_node = try allocator.create(Node);
    attr_node.* = Node{ .attribute = attr };
    try child.setAttributeNode(@constCast(&Node{ .element = @constCast(&child) }), attr_node);
    var grandchild = Element.init(allocator, "grandchild");
    defer grandchild.deinit();

    const grandchild_node = try allocator.create(Node);
    grandchild_node.* = Node{ .element = &grandchild };
    const child_parent_node = try allocator.create(Node);
    child_parent_node.* = Node{ .element = &child };
    _ = try child.appendChild(child_parent_node, grandchild_node);
    const root_parent_node = try allocator.create(Node);
    root_parent_node.* = Node{ .element = &root };
    const child_node = try allocator.create(Node);
    child_node.* = Node{ .element = &child };
    _ = try root.appendChild(root_parent_node, child_node);
    const root_node = try allocator.create(Node);
    root_node.* = Node{ .element = &root };
    try doc.children.append(root_node);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&doc, ast);
    defer result.deinit();

    // Verify results
    try testing.expectEqual(@as(usize, 1), result.nodes.items.len);
    try testing.expectEqual(NodeType.element, result.nodes.items[0].getNodeType());
    try testing.expectEqualStrings("grandchild", result.nodes.items[0].element.tagName);
}

test "XPathEvaluator: no matching nodes" {
    const allocator = testing.allocator;

    // Create XML document
    var doc = Document.init(allocator);
    defer doc.deinit();

    var root = Element.init(allocator, "root");
    defer root.deinit();
    var child = Element.init(allocator, "child");
    defer child.deinit();
    const attr = try allocator.create(Attr);
    attr.* = Attr.init("attr", "wrong", null);
    const attr_node = try allocator.create(Node);
    attr_node.* = Node{ .attribute = attr };
    _ = try child.setAttributeNode(@constCast(&Node{ .element = @constCast(&child) }), attr_node);

    const child_node = try allocator.create(Node);
    child_node.* = Node{ .element = &child };
    const root_parent_node = try allocator.create(Node);
    root_parent_node.* = Node{ .element = &root };
    _ = try root.appendChild(root_parent_node, child_node);
    const root_node = try allocator.create(Node);
    root_node.* = Node{ .element = &root };
    try doc.children.append(root_node);

    // Parse and evaluate XPath
    const xpath_str = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&doc, ast);
    defer result.deinit();

    // Verify no matches
    try testing.expectEqual(@as(usize, 0), result.nodes.items.len);
}

test "XPathEvaluator: empty document" {
    const allocator = testing.allocator;

    // Create empty document
    var doc = Document.init(allocator);
    defer doc.deinit();

    // Parse and evaluate XPath
    const xpath_str = "/root";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(xpath_str);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var evaluator = XPathEvaluator.init(allocator);
    var result = try evaluator.evaluate(&doc, ast);
    defer result.deinit();

    // Verify no matches
    try testing.expectEqual(@as(usize, 0), result.nodes.items.len);
}
