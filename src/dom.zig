const std = @import("std");

const Allocator = std.mem.Allocator;
const WriteError = std.fs.File.WriteError;
const RenderError = WriteError || error{OutOfMemory};

pub const NodeType = enum(u8) {
    element = 1,
    attribute = 2,
    text = 3,
    // cdata_section_node = 4,
    // processing_instruction_node = 7,
    // comment_node = 8,
    document = 9,
};

pub const Node = union(NodeType) {
    element: *Element,
    attribute: *Attr,
    text: *Text,
    document: *Document,

    pub fn deinit(self: Node) void {
      switch (self) {
          .document => self.document.deinit(),
          .element => self.element.deinit(),
          else => {}
      }
    }

    pub fn getNodeType(self: Node) NodeType {
        return switch (self) {
            .document => self.document.nodeType,
            .element => self.element.nodeType,
            .text => self.text.nodeType,
            .attribute => self.attribute.nodeType,
        };
    }

    pub fn render(self: Node, writer: anytype) RenderError!void {
        switch (self) {
            .document => try self.document.render(writer),
            .element => try self.element.render(writer),
            .text => try self.text.render(writer),
            .attribute => try self.attribute.render(writer),
        }
    }
};

pub const Document = struct {
    nodeType: NodeType = .document,
    children: std.ArrayList(Node),

    pub fn init(allocator: Allocator) Document {
        return Document{
            .children = std.ArrayList(Node).init(allocator),
        };
    }

    pub fn deinit(self: *Document) void {
        self.children.deinit();
    }

    pub fn render(self: Document, writer: anytype) RenderError!void {
        for (self.children.items) |child| {
            try child.render(writer);
        }
    }
};

pub const Element = struct {
    nodeType: NodeType = .element,
    tagName: []const u8,
    attributes: std.ArrayList(Attr) = undefined,
    children: std.ArrayList(Node) = undefined,
    parentElement: ?*Element = null,

    pub fn init(allocator: Allocator, tagName: []const u8) Element {
        return Element{
            .tagName = tagName,
            .attributes = std.ArrayList(Attr).init(allocator),
            .children = std.ArrayList(Node).init(allocator),
            .parentElement = null,
        };
    }

    pub fn deinit(self: *Element) void {
        self.attributes.deinit();
        self.children.deinit();
    }

    pub fn appendChild(self: *Element, child: *Node) !*Node {
        switch (child.*) {
            .document => {},
            .element => |e| e.parentElement = self,
            .text => |t| t.parentElement = self,
            .attribute => |a| a.parentElement = self,
        }

        try self.children.append(child.*);
        return child;
    }

    pub fn setAttribute(self: *Element, name: []const u8, value: []const u8) !void {
        // Check if attribute already exists
        for (self.attributes.items) |*attr| {
            if (std.mem.eql(u8, attr.name, name)) {
                attr.value = value;
                return;
            }
        }
        // Add new attribute
        try self.attributes.append(Attr{
            .name = name,
            .value = value,
            .parentElement = self,
        });
    }

    pub fn getAttribute(self: *Element, name: []const u8) ?[]const u8 {
        for (self.attributes.items) |attr| {
            if (std.mem.eql(u8, attr.name, name)) {
                return attr.value;
            }
        }
        return null;
    }

    pub fn render(self: Element, writer: anytype) RenderError!void {
        try writer.print("<{s}", .{self.tagName});
        for (self.attributes.items) |attr| {
            try attr.render(writer);
        }
        try writer.print(">", .{});
        for (self.children.items) |child| {
            try child.render(writer);
        }
        try writer.print("</{s}>", .{self.tagName});
    }
};

pub const Text = struct {
    nodeType: NodeType = .text,
    content: []const u8,
    parentElement: ?*Element = null,

    fn render(self: Text, writer: anytype) RenderError!void {
        try writer.print("{s}", .{self.content});
    }
};

pub const Attr = struct {
    nodeType: NodeType = .attribute,
    name: []const u8,
    value: []const u8,
    parentElement: ?*Element = null,

    fn render(self: Attr, writer: anytype) RenderError!void {
        try writer.print(" {s}=\"{s}\"", .{ self.name, self.value });
    }
};

const testing = std.testing;

test "Node.getNodeType returns correct node type" {
    var doc = Document.init(testing.allocator);
    var elem = Element.init(testing.allocator, "div");
    var text = Text{ .content = "Hello" };
    var attr = Attr{ .name = "id", .value = "test" };

    var doc_node = Node{ .document = &doc };
    var elem_node = Node{ .element = &elem };
    var text_node = Node{ .text = &text };
    var attr_node = Node{ .attribute = &attr };

    try testing.expectEqual(NodeType.document, doc_node.getNodeType());
    try testing.expectEqual(NodeType.element, elem_node.getNodeType());
    try testing.expectEqual(NodeType.text, text_node.getNodeType());
    try testing.expectEqual(NodeType.attribute, attr_node.getNodeType());
}

test "Element.init creates element with correct properties" {
    const elem = Element.init(testing.allocator, "div");
    try testing.expectEqualStrings("div", elem.tagName);
    try testing.expectEqual(NodeType.element, elem.nodeType);
    try testing.expectEqual(@as(usize, 0), elem.attributes.items.len);
    try testing.expectEqual(@as(usize, 0), elem.children.items.len);
    try testing.expectEqual(@as(?*Element, null), elem.parentElement);
}

test "Element.setAttribute and getAttribute work correctly" {
    var elem = Element.init(testing.allocator, "div");
    try elem.setAttribute("id", "test");
    try elem.setAttribute("class", "container");

    try testing.expectEqualStrings("test", elem.getAttribute("id").?);
    try testing.expectEqualStrings("container", elem.getAttribute("class").?);
    try testing.expectEqual(@as(?[]const u8, null), elem.getAttribute("style"));
    try elem.setAttribute("id", "new-id");
    try testing.expectEqualStrings("new-id", elem.getAttribute("id").?);
    try testing.expectEqual(@as(usize, 2), elem.attributes.items.len);
    elem.deinit();
}

test "Element.appendChild sets parent and adds child" {
    var parent = Element.init(testing.allocator, "div");
    var child_elem = Element.init(testing.allocator, "span");
    var text = Text{ .content = "Hello" };

    var child_node = Node{ .element = &child_elem };
    var text_node = Node{ .text = &text };

    _ = try parent.appendChild(&child_node);
    try testing.expectEqual(@as(usize, 1), parent.children.items.len);
    try testing.expectEqual(&parent, child_elem.parentElement);

    _ = try parent.appendChild(&text_node);
    try testing.expectEqual(@as(usize, 2), parent.children.items.len);
    try testing.expectEqual(&parent, text.parentElement);
    parent.deinit();
    child_elem.deinit();
}

test "Render simple element with attributes and text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var elem = Element.init(allocator, "div");
    try elem.setAttribute("id", "test");
    var text = Text{ .content = "Hello, World!" };
    var text_node = Node{ .text = &text };
    _ = try elem.appendChild(&text_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try elem.render(buffer.writer());

    const expected = "<div id=\"test\">Hello, World!</div>";
    try testing.expectEqualStrings(expected, buffer.items);
}

test "Render nested elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parent = Element.init(allocator, "div");
    try parent.setAttribute("class", "container");

    var child = Element.init(allocator, "span");
    var text = Text{ .content = "Nested" };
    var text_node = Node{ .text = &text };
    var child_node = Node{ .element = &child };

    _ = try child.appendChild(&text_node);
    _ = try parent.appendChild(&child_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try parent.render(buffer.writer());

    const expected = "<div class=\"container\"><span>Nested</span></div>";
    try testing.expectEqualStrings(expected, buffer.items);
}

test "Document renders children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var doc = Document.init(allocator);
    var elem = Element.init(allocator, "p");
    var text = Text{ .content = "Document content" };
    var text_node = Node{ .text = &text };
    const elem_node = Node{ .element = &elem };

    _ = try elem.appendChild(&text_node);
    try doc.children.append(elem_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try doc.render(buffer.writer());

    const expected = "<p>Document content</p>";
    try testing.expectEqualStrings(expected, buffer.items);
}
