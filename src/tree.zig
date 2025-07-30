const std = @import("std");

const Allocator = std.mem.Allocator;

pub const NodeList = std.ArrayList(*Node);
pub const NamedNodeMap = std.AutoArrayHashMap([]const u8, [:0]const u8);

// Define structs outside the union to avoid recursive dependency
pub const Element = struct {
    alloc: Allocator,
    name: [:0]const u8,
    attributes: *NamedNodeMap,
    children: *NodeList,
    parent: ?*Node = null,

    fn init(alloc: Allocator, tag: []const u8) !Element {
        const name = try alloc.dupeZ(u8, tag);
        const attrs = try alloc.create(NamedNodeMap);
        attrs.* = NamedNodeMap.init(alloc);
        const kids = try alloc.create(NodeList);
        kids.* = NodeList.init(alloc);
        return .{ .alloc = alloc, .name = name, .attributes = attrs, .children = kids };
    }

    fn deinit(self: *Element) void {
        self.alloc.free(self.name);
        for (self.children.items) |child| {
            child.deinit();
            self.alloc.destroy(child);
        }
        self.children.deinit();
        self.alloc.destroy(self.children);
        self.attributes.deinit();
        self.alloc.destroy(self.attributes);
    }
};

pub const Attribute = struct {
    name: [:0]const u8,
    value: [:0]const u8, // Changed from [*:0]const u8 to [:0]const u8 for consistency
    parent: ?*Node = null,

    fn init(alloc: Allocator, name: []const u8, value: []const u8) !Attribute {
        const name_copy = try alloc.dupeZ(u8, name);
        const value_copy = try alloc.dupeZ(u8, value);
        return .{ .name = name_copy, .value = value_copy };
    }

    fn deinit(self: *Attribute, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.value);
    }
};

pub const CharData = struct {
    content: [:0]const u8, // Changed from [*:0]const u8 to [:0]const u8
    parent: ?*Node = null,

    fn init(alloc: Allocator, content: []const u8) !CharData {
        const content_copy = try alloc.dupeZ(u8, content);
        return .{ .content = content_copy };
    }

    fn deinit(self: *CharData, alloc: Allocator) void {
        alloc.free(self.content);
    }
};

pub const Document = struct {
    alloc: Allocator,
    children: *NodeList,

    fn init(alloc: Allocator) !Document {
        const kids = try alloc.create(NodeList);
        kids.* = NodeList.init(alloc);
        return .{ .alloc = alloc, .children = kids };
    }

    fn deinit(self: *Document) void {
        for (self.children.items) |child| {
            child.deinit();
            self.alloc.destroy(child);
        }
        self.children.deinit();
        self.alloc.destroy(self.children);
    }
};

pub const NodeType = enum(u8) {
    element = 1,
    attribute = 2,
    text = 3,
    cdata = 4,
    proc_inst = 7,
    comment = 8,
    document = 9,
};

pub const Node = union(NodeType) {
    element: Element,
    attribute: Attribute,
    text: CharData,
    cdata: CharData,
    proc_inst: CharData,
    comment: CharData,
    document: Document,

    // Constructors
    pub fn Elem(alloc: Allocator, tag: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .element = try Element.init(alloc, tag) };
        return node;
    }

    pub fn Attr(alloc: Allocator, name: []const u8, value: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .attribute = try Attribute.init(alloc, name, value) };
        return node;
    }

    pub fn Text(alloc: Allocator, content: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .text = try CharData.init(alloc, content) };
        return node;
    }

    pub fn CData(alloc: Allocator, content: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .cdata = try CharData.init(alloc, content) };
        return node;
    }

    pub fn ProcInst(alloc: Allocator, content: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .proc_inst = try CharData.init(alloc, content) };
        return node;
    }

    pub fn Comment(alloc: Allocator, content: []const u8) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .comment = try CharData.init(alloc, content) };
        return node;
    }

    pub fn Doc(alloc: Allocator) !*Node {
        const node = try alloc.create(Node);
        node.* = .{ .document = try Document.init(alloc) };
        return node;
    }

    // Node methods
    pub fn archetype(n: Node) NodeType {
        return @as(NodeType, n);
    }

    pub fn parent(n: *Node) ?*Node {
        return switch (n.*) {
            .element => |e| e.parent,
            .attribute => |a| a.parent,
            .text => |t| t.parent,
            .cdata => |c| c.parent,
            .proc_inst => |p| p.parent,
            .comment => |c| c.parent,
            .document => null,
        };
    }

    fn allocator(n: *Node) ?Allocator {
        return switch (n.*) {
            .element => |e| e.alloc,
            .document => |d| d.alloc,
            .attribute => |a| if (a.parent) |p| p.allocator() else null,
            .text => |t| if (t.parent) |p| p.allocator() else null,
            .cdata => |c| if (c.parent) |p| p.allocator() else null,
            .proc_inst => |p| if (p.parent) |p_| p_.allocator() else null,
            .comment => |c| if (c.parent) |p| p.allocator() else null,
        };
    }

    pub fn deinit(n: *Node) void {
        switch (n.*) {
            .element => |*e| e.deinit(),
            .attribute => |*a| if (n.allocator()) |alloc| a.deinit(alloc),
            .text => |*t| if (n.allocator()) |alloc| t.deinit(alloc),
            .cdata => |*c| if (n.allocator()) |alloc| c.deinit(alloc),
            .proc_inst => |*p| if (n.allocator()) |alloc| p.deinit(alloc),
            .comment => |*c| if (n.allocator()) |alloc| c.deinit(alloc),
            .document => |*d| d.deinit(),
        }
    }

    // Inner nodes: Elem & Doc
    pub fn children(n: Node) *NodeList {
        return switch (n) {
            .element => |e| e.children,
            .document => |d| d.children,
            else => unreachable,
        };
    }

    pub fn append(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .proc_inst);
        child.parent = n;
        switch (n.*) {
            .element => |*e| try e.children.append(child),
            .document => |*d| try d.children.append(child),
            else => unreachable,
        }
    }

    pub fn prepend(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .proc_inst);
        child.parent = n;
        switch (n.*) {
            .element => |*e| try e.children.prepend(child),
            .document => |*d| try d.children.prepend(child),
            else => unreachable,
        }
    }

    // Named nodes: Elem & Attr
    pub fn getName(n: Node) [:0]const u8 {
        return switch (n) {
            .element => |e| e.name,
            .attribute => |a| a.name,
            else => unreachable,
        };
    }

    // Elem
    pub fn attributes(n: Node) *NamedNodeMap {
        return switch (n) {
            .element => |e| e.attributes,
            else => unreachable,
        };
    }

    // Value Nodes: Attr, Text, CData, Comment, ProcInst
    pub fn setValue(n: *Node, value: [:0]const u8) !void {
        switch (n.*) {
            .attribute => |*a| {
                if (n.allocator()) |alloc| {
                    alloc.free(a.value);
                    a.value = try alloc.dupeZ(u8, value);
                }
            },
            .text => |*t| {
                if (n.allocator()) |alloc| {
                    alloc.free(t.content);
                    t.content = try alloc.dupeZ(u8, value);
                }
            },
            .cdata => |*c| {
                if (n.allocator()) |alloc| {
                    alloc.free(c.content);
                    c.content = try alloc.dupeZ(u8, value);
                }
            },
            .comment => |*c| {
                if (n.allocator()) |alloc| {
                    alloc.free(c.content);
                    c.content = try alloc.dupeZ(u8, value);
                }
            },
            .proc_inst => |*p| {
                if (n.allocator()) |alloc| {
                    alloc.free(p.content);
                    p.content = try alloc.dupeZ(u8, value);
                }
            },
            else => unreachable,
        }
    }

    pub fn getValue(n: Node) [:0]const u8 {
        return switch (n) {
            .attribute => |a| a.value,
            .text => |t| t.content,
            .cdata => |c| c.content,
            .comment => |c| c.content,
            .proc_inst => |p| p.content,
            else => unreachable,
        };
    }

    // Render
    pub fn render(n: Node, writer: anytype) !void {
        switch (n) {
            .element => |e| {
                try writer.print("<{s}", .{e.name});
                for (e.attributes.keys(), 0..) |key, i| {
                    if (i != 0) try writer.print(" ", .{});
                    try writer.print("{s}=\"{s}\"", .{key, e.attributes.get(key).?});
                }
                try writer.print(">", .{});
                for (e.children.items) |child| try child.render(writer);
                try writer.print("</{s}>", .{e.name});
            },
            .attribute => |a| try writer.print("{s}=\"{s}\"", .{a.name, a.value}),
            .text => |t| try writer.print("{s}", .{t.content}),
            .cdata => |c| try writer.print("<![CDATA[{s}]]>", .{c.content}),
            .proc_inst => |p| try writer.print("<?{s}?>", .{p.content}),
            .comment => |c| try writer.print("<!--{s}-->", .{c.content}),
            .document => |d| for (d.children.items) |child| try child.render(writer),
        }
    }
};

const testing = std.testing;

test "Node.archetype" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.deinit();
    try testing.expectEqual(NodeType.element, elem.archetype());

    var attr = try Node.Attr(testing.allocator, "id", "1");
    defer attr.deinit();
    try testing.expectEqual(NodeType.attribute, attr.archetype());

    var text = try Node.Text(testing.allocator, "Hello");
    defer text.deinit();
    try testing.expectEqual(NodeType.text, text.archetype());

    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.deinit();
    try testing.expectEqual(NodeType.cdata, cdata.archetype());

    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.deinit();
    try testing.expectEqual(NodeType.proc_inst, procinst.archetype());

    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.deinit();
    try testing.expectEqual(NodeType.comment, comment.archetype()); // Fixed from .cdata to .comment

    var doc = try Node.Doc(testing.allocator);
    defer doc.deinit();
    try testing.expectEqual(NodeType.document, doc.archetype());
}

test "Node.parent" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.deinit();
    try testing.expectEqual(null, elem.parent());

    var attr = try Node.Attr(testing.allocator, "id", "1");
    defer attr.deinit();
    try testing.expectEqual(null, attr.parent());

    var text = try Node.Text(testing.allocator, "Hello");
    defer text.deinit();
    try testing.expectEqual(null, text.parent());

    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.deinit();
    try testing.expectEqual(null, cdata.parent());

    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.deinit();
    try testing.expectEqual(null, procinst.parent());

    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.deinit();
    try testing.expectEqual(null, comment.parent());

    var doc = try Node.Doc(testing.allocator);
    defer doc.deinit();
    try testing.expectEqual(null, doc.parent());
}

test "Elem.getName" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.deinit();
    try testing.expectEqualStrings("div", elem.getName());
}

test "Attribute.getName" {
    var attr = try Node.Attr(testing.allocator, "title", "Mr");
    defer attr.deinit();
    try testing.expectEqualStrings("title", attr.getName());
}

test "Element.attributes" {}
test "Element.append" {}
test "Element.prepend" {}
test "Element.children" {}
test "Attribute.getValue" {}
test "Attribute.setValue" {}
test "Text.getValue" {}
test "Text.setValue" {}
test "Comment.getValue" {}
test "Comment.setValue" {}
test "ProcInst.getValue" {}
test "ProcInst.setValue" {}
test "Doc.append" {}
test "Doc.prepend" {}
test "Doc.children" {}
