const std = @import("std");

const Allocator = std.mem.Allocator;

pub const NodeList = std.ArrayList(*Node);
pub const NamedNodeMap = std.AutoArrayHashMap([]const u8, [:0]const u8);

const Element = struct {
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

const Attribute = struct {
    alloc: Allocator, // Added allocator field
    name: [:0]const u8,
    value: [:0]const u8,
    parent: ?*Node = null,

    fn init(alloc: Allocator, name: []const u8, value: []const u8) !Attribute {
        const name_copy = try alloc.dupeZ(u8, name);
        const value_copy = try alloc.dupeZ(u8, value);
        return .{ .alloc = alloc, .name = name_copy, .value = value_copy };
    }

    fn deinit(self: *Attribute) void {
        self.alloc.free(self.name);
        self.alloc.free(self.value);
    }
};

const CharData = struct {
    alloc: Allocator, // Added allocator field
    content: [:0]const u8,
    parent: ?*Node = null,

    fn init(alloc: Allocator, content: []const u8) !CharData {
        const content_copy = try alloc.dupeZ(u8, content);
        return .{ .alloc = alloc, .content = content_copy };
    }

    fn deinit(self: *CharData) void {
        self.alloc.free(self.content);
    }
};

const Document = struct {
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

    // private
    fn setParent(n: *Node, m: ?*Node) void {
      std.debug.assert(n.* == .element or n.* == .attribute or n.* == .text or n.* == .cdata or n.* == .comment or n.* == .proc_inst);
      std.debug.assert(m == null or m.?.* == .element or m.?.* == .document or m.?.* == .attribute);
      switch (n.*) {
          .element => |*e| e.parent = m,
          .attribute => |*a| a.parent = m,
          .text => |*t| t.parent = m,
          .cdata => |*c| c.parent = m,
          .proc_inst => |*p| p.parent = m,
          .comment => |*c| c.parent = m,
          .document => {},
      }
    }

    fn allocator(n: *Node) Allocator {
        return switch (n.*) {
            .element => |e| e.alloc,
            .attribute => |a| a.alloc,
            .text => |t| t.alloc,
            .cdata => |c| c.alloc,
            .proc_inst => |p| p.alloc,
            .comment => |c| c.alloc,
            .document => |d| d.alloc,
        };
    }

    pub fn deinit(n: *Node) void {
        switch (n.*) {
            .element => |*e| e.deinit(),
            .attribute => |*a| a.deinit(),
            .text => |*t| t.deinit(),
            .cdata => |*c| c.deinit(),
            .proc_inst => |*p| p.deinit(),
            .comment => |*c| c.deinit(),
            .document => |*d| d.deinit(),
        }
    }

    fn destroy(n: *Node) void {
        const alloc = n.allocator();
        n.deinit();
        alloc.destroy(n);
    }

    // Inner nodes: Elem & Doc

    pub fn count(n: Node) usize {
        return switch (n) {
            .element => |e| e.children.items.len,
            .document => |d| d.children.items.len,
            else => unreachable,
        };
    }

    pub fn children(n: Node) *NodeList {
        return switch (n) {
            .element => |e| e.children,
            .document => |d| d.children,
            else => unreachable,
        };
    }

    // Remove a node from its current parent, if any
    fn detach(n: *Node) void {
        if (n.parent()) |ancestor| {
            switch (ancestor.*) {
                .element => |*e| {
                    // Find and remove the node from the children list
                    for (e.children.items, 0..) |child, i| {
                        if (child == n) {
                            _ = e.children.orderedRemove(i);
                            break;
                        }
                    }
                },
                .document => |*d| {
                    for (d.children.items, 0..) |child, i| {
                        if (child == n) {
                            _ = d.children.orderedRemove(i);
                            break;
                        }
                    }
                },
                else => unreachable,
            }
            n.setParent(null);
        }
    }

    pub fn append(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or
                          child.* == .comment or child.* == .proc_inst);
        child.detach();
        child.setParent(n);
        switch (n.*) {
            .element => |*e| try e.children.append(child),
            .document => |*d| try d.children.append(child),
            else => unreachable,
        }
    }

    pub fn prepend(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or
                          child.* == .comment or child.* == .proc_inst);
        child.detach();
        child.setParent(n);
        switch (n.*) {
            .element => |*e| try e.children.insert(0, child),
            .document => |*d| try d.children.insert(0, child),
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
        const alloc = n.allocator();
        switch (n.*) {
            .attribute => |*a| {
                alloc.free(a.value);
                a.value = try alloc.dupeZ(u8, value);
            },
            .text => |*t| {
                alloc.free(t.content);
                t.content = try alloc.dupeZ(u8, value);
            },
            .cdata => |*c| {
                alloc.free(c.content);
                c.content = try alloc.dupeZ(u8, value);
            },
            .comment => |*c| {
                alloc.free(c.content);
                c.content = try alloc.dupeZ(u8, value);
            },
            .proc_inst => |*p| {
                alloc.free(p.content);
                p.content = try alloc.dupeZ(u8, value);
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
    defer elem.destroy();
    try testing.expectEqual(NodeType.element, elem.archetype());

    var attr = try Node.Attr(testing.allocator, "id", "1");
    defer attr.destroy();
    try testing.expectEqual(NodeType.attribute, attr.archetype());

    var text = try Node.Text(testing.allocator, "Hello");
    defer text.destroy();
    try testing.expectEqual(NodeType.text, text.archetype());

    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.destroy();
    try testing.expectEqual(NodeType.cdata, cdata.archetype());

    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.destroy();
    try testing.expectEqual(NodeType.proc_inst, procinst.archetype());

    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.destroy();
    try testing.expectEqual(NodeType.comment, comment.archetype());

    var doc = try Node.Doc(testing.allocator);
    defer doc.destroy();
    try testing.expectEqual(NodeType.document, doc.archetype());
}

test "Node.parent" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();
    try testing.expectEqual(null, elem.parent());

    var attr = try Node.Attr(testing.allocator, "id", "1");
    defer attr.destroy();
    try testing.expectEqual(null, attr.parent());

    var text = try Node.Text(testing.allocator, "Hello");
    defer text.destroy();
    try testing.expectEqual(null, text.parent());

    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.destroy();
    try testing.expectEqual(null, cdata.parent());

    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.destroy();
    try testing.expectEqual(null, procinst.parent());

    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.destroy();
    try testing.expectEqual(null, comment.parent());

    var doc = try Node.Doc(testing.allocator);
    defer doc.destroy();
    try testing.expectEqual(null, doc.parent());
}

test "Elem.getName" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();
    try testing.expectEqualStrings("div", elem.getName());
}

test "Attribute.getName" {
    var attr = try Node.Attr(testing.allocator, "title", "Mr");
    defer attr.destroy();
    try testing.expectEqualStrings("title", attr.getName());
}

test "Node.append" {
    var doc = try Node.Doc(testing.allocator);
    defer doc.destroy();

    const elem = try Node.Elem(testing.allocator, "div");
    const text = try Node.Text(testing.allocator, "Hello");

    try Node.append(doc, elem);
    try Node.append(doc, text);

    try std.testing.expectEqual(2, Node.count(doc.*));
}

test "Doc.prepend" {
    var doc = try Node.Doc(testing.allocator);
    defer doc.destroy();

    const elem = try Node.Elem(testing.allocator, "div");
    const text = try Node.Text(testing.allocator, "Hello");

    try Node.prepend(doc, elem);
    try Node.prepend(doc, text);

    try std.testing.expectEqual(2, Node.count(doc.*));
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
test "Doc.children" {}
