const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ArrayList = std.ArrayList;
pub const StringArrayHashMap = std.StringArrayHashMap;

const Element = struct {
    alloc: Allocator,
    name: [:0]const u8,
    attributes: NamedNodeMap,
    children: NodeList,
    parent: ?*Node = null,

    fn init(alloc: Allocator, tag: []const u8) !Element {
        const name = try alloc.dupeZ(u8, tag);
        const attrs = try alloc.create(NamedNodeMap);
        attrs.* = try NamedNodeMap.init(alloc);
        const kids = try alloc.create(NodeList);
        kids.* = ArrayList(*Node).init(alloc);
        return .{ .alloc = alloc, .name = name, .attributes = attrs, .children = kids };
    }

    fn deinit(elem: *Element) void {
        elem.alloc.free(elem.name);
        elem.children.destroy();
        elem.attributes.destroy();
    }

    fn getAttribute(elem: *Element, name: [:0]const u8) *Node {
      return elem.attributes.getNamedItem(name);
    }

    fn setAttribute(elem: *Element, name: [:0]const u8, value: [:0]const u8) void {
      if (elem.getAttribute(name)) |attr|
        return attr.setValue(value);
    }
};

const Attribute = struct {
    alloc: Allocator,
    name: [:0]const u8,
    value: [:0]const u8,
    parent: ?*Node = null,

    fn init(alloc: Allocator, name: []const u8, value: []const u8) !Attribute {
        const name_copy = try alloc.dupeZ(u8, name);
        const value_copy = try alloc.dupeZ(u8, value);
        return .{ .alloc = alloc, .name = name_copy, .value = value_copy };
    }

    fn deinit(attr: *Attribute) void {
        attr.alloc.free(attr.name);
        attr.alloc.free(attr.value);
    }

    fn setValue(attr: Attribute,  value: [:0]const u8) void {
        attr.alloc.free(attr.value);
        attr.value = try attr.alloc.dupeZ(u8, value);
    }
};

const CharData = struct {
    alloc: Allocator,
    content: [:0]const u8,
    parent: ?*Node = null,

    fn init(alloc: Allocator, content: []const u8) !CharData {
        const content_copy = try alloc.dupeZ(u8, content);
        return .{ .alloc = alloc, .content = content_copy };
    }

    fn deinit(char: *CharData) void {
        char.alloc.free(char.content);
    }

    fn setContent(char: CharData,  value: [:0]const u8) void {
        char.alloc.free(char.content);
        char.content = try char.alloc.dupeZ(u8, value);
    }
};

const Document = struct {
    alloc: Allocator,
    children: *NodeList,

    fn init(alloc: Allocator) !Document {
        const kids = try alloc.create(NodeList);
        kids.* = try NodeList.init(alloc);
        return .{ .alloc = alloc, .children = kids };
    }

    fn deinit(doc: *Document) void {
        doc.children.deinit();
    }

    fn destroy(doc: *Document) void {
        doc.children.deinit();
        doc.children.destroy();
    }
};

pub const NodeList = struct {
  alloc: Allocator,
  children: ArrayList(*Node),

  fn init(alloc: Allocator) !NodeList {
      const kids = try alloc.create(ArrayList(*Node));
      kids.* = ArrayList(*Node).init(alloc);
      return .{ .alloc = alloc, .children = kids };
  }

  fn deinit(self: *NodeList) void {
    for (self.children.items) |child| {
        child.deinit();
        self.alloc.destroy(child);
    }
    self.children.deinit();
  }

  fn destroy(self: *NodeList) void {
    self.deinit();
    self.alloc.destroy(self.children);
  }

  fn remove(self: *NodeList, item: *Node) void {
    for (self.children.items, 0..) |child, i| {
        if (child == item) {
            _ = self.children.orderedRemove(i);
            break;
        }
    }
  }
};

pub const NamedNodeMap = struct {
  alloc: Allocator,
  items: ArrayList(*Node),
  // names: ArrayList([:0]const u8),

  pub fn keys(_: *NamedNodeMap) ArrayList([:0]const u8) {
    // TODO, change type if you like
    // loop over items and collect name of attributes
  }

  pub fn values(_: *NamedNodeMap) ArrayList(*Node) {
    // TODO, change type if you like
    // // loop over items and collect value of attributes
  }

  fn init(alloc: Allocator) !NodeList {
      const attrs = try alloc.create(ArrayList(*Node));
      attrs.* = StringArrayHashMap(ArrayList(*Node)).init(alloc);
      return .{ .alloc = alloc, .items = attrs };
  }

  fn destroy(self: *NamedNodeMap) void {
    for (self.items.values()) |value|
        self.alloc.free(value);
    self.items.deinit();
    self.alloc.destroy(self.items);
  }

  fn getNamedItem(self: *NamedNodeMap, name: [:0]const u8) ?*Node {
    for (self.keys(), 0..) |n,i|
      if (std.mem.eql([:0]const u8, name, n))
        return self.items[i];
  }

  fn setNamedItem(self: *NamedNodeMap, item: *Node) void {
    std.debug.assert(item.* == .attribute);
    if (self.getNamedItem()) |n| n.setValue(item.getValue());
    _ = self.getNamedItem();
    // TODO
    // find the attr node in self.names with name
    // if exists change
    // if non exists, create a new attr node
  }

  fn removeNamedItem(_: *NamedNodeMap) void {
    // TODO
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

    fn destroy(n: *Node) void {
        const alloc = n.allocator();
        n.deinit();
        alloc.destroy(n);
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

    fn setParent(n: *Node, m: ?*Node) void {
        std.debug.assert(m == null or m.?.* == .element or m.?.* == .document or m.?.* == .attribute);
        switch (n.*) {
            .element => |*e| e.parent = m,
            .attribute => |*a| a.parent = m,
            .text => |*t| t.parent = m,
            .cdata => |*c| c.parent = m,
            .proc_inst => |*p| p.parent = m,
            .comment => |*c| c.parent = m,
            .document => undefined,
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
                .element => |*e| e.remove(n),
                .document => |*d| d.remove(n),
                else => unreachable,
            }
            n.setParent(null);
        }
    }

    pub fn append(n: *Node, child: *Node) !void {
        std.debug.assert(child.* != .document or child.* != .attribute);
        child.detach();
        child.setParent(n);
        switch (n.*) {
            .element => |*e| try e.children.append(child),
            .document => |*d| try d.children.append(child),
            else => unreachable,
        }
    }

    pub fn prepend(n: *Node, child: *Node) !void {
        std.debug.assert(child.* != .document or child.* != .attribute);
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

    pub fn getAttribute(n: *Node, name: [:0]const u8) ?[:0]const u8 {
        return switch (n.*) {
            .element => |e| e.attributes.get(name),
            else => unreachable,
        };
    }

    pub fn setAttribute(n: *Node, name: []const u8, value: []const u8) !void {
        switch (n.*) {
            .element => |*e| e.setAttribute(name, value),
            else => unreachable,
        }
    }

    // Value Nodes: Attr, Text, CData, Comment, ProcInst
    pub fn setValue(n: *Node, value: [:0]const u8) !void {
        switch (n.*) {
            .attribute => |*a| a.setValue(value),
            .text => |*t| t.setContent(value),
            .cdata => |*c| c.setContent(value),
            .comment => |*c| c.setContent(value),
            .proc_inst => |*p| p.setContent(value),
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

test "Elem.append" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();

    const elem2 = try Node.Elem(testing.allocator, "div");
    const text = try Node.Text(testing.allocator, "Hello");

    try Node.append(elem, elem2);
    try Node.append(elem, text);

    try std.testing.expectEqual(2, Node.count(elem.*));
}

test "Elem.prepend" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();

    const elem2 = try Node.Elem(testing.allocator, "div");
    const text = try Node.Text(testing.allocator, "Hello");

    try Node.prepend(elem, elem2);
    try Node.prepend(elem, text);

    try std.testing.expectEqual(2, Node.count(elem.*));
}

test "Element.getAttribute" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();

    try testing.expectEqual(null, elem.getAttribute("id"));

    try elem.setAttribute("id", "main");
    try testing.expectEqualStrings("main", elem.getAttribute("id").?);
}

test "Element.setAttribute" {
    var elem = try Node.Elem(testing.allocator, "div");
    defer elem.destroy();

    // Set a new attribute
    try elem.setAttribute("id", "main");
    try testing.expectEqualStrings("main", elem.getAttribute("id").?);

    // Update existing attribute
    try elem.setAttribute("id", "content");
    try testing.expectEqualStrings("content", elem.getAttribute("id").?);

    // Add another attribute
    try elem.setAttribute("class", "container");
    try testing.expectEqualStrings("container", elem.getAttribute("class").?);
}

test "Doc.append" {
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

test "Attribute.getName" {
    var attr = try Node.Attr(testing.allocator, "title", "Mr");
    defer attr.destroy();
    try testing.expectEqualStrings("title", attr.getName());
}

test "Attribute.getValue" {
    var attr = try Node.Attr(testing.allocator, "title", "Mr");
    defer attr.destroy();
    try testing.expectEqualStrings("Mr", attr.getValue());
}

test "Attribute.setValue" {
    var attr = try Node.Attr(testing.allocator, "title", "Mr");
    defer attr.destroy();

    try attr.setValue("Ms");
    try testing.expectEqualStrings("Ms", attr.getValue());
}

test "Text.getValue" {
    var text = try Node.Text(testing.allocator, "Hello");
    defer text.destroy();
    try testing.expectEqualStrings("Hello", text.getValue());
}

test "Text.setValue" {
    var text = try Node.Text(testing.allocator, "Hello");
    defer text.destroy();

    try text.setValue("World");
    try testing.expectEqualStrings("World", text.getValue());
}

test "CData.getValue" {
    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.destroy();
    try testing.expectEqualStrings("DATA", cdata.getValue());
}

test "CData.setValue" {
    var cdata = try Node.CData(testing.allocator, "DATA");
    defer cdata.destroy();

    try cdata.setValue("NEW_DATA");
    try testing.expectEqualStrings("NEW_DATA", cdata.getValue());
}

test "Comment.getValue" {
    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.destroy();
    try testing.expectEqualStrings("Help", comment.getValue());
}

test "Comment.setValue" {
    var comment = try Node.Comment(testing.allocator, "Help");
    defer comment.destroy();

    try comment.setValue("Info");
    try testing.expectEqualStrings("Info", comment.getValue());
}

test "ProcInst.getValue" {
    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.destroy();
    try testing.expectEqualStrings("xml version=\"1.0\"", procinst.getValue());
}

test "ProcInst.setValue" {
    var procinst = try Node.ProcInst(testing.allocator, "xml version=\"1.0\"");
    defer procinst.destroy();

    try procinst.setValue("xml version=\"2.0\"");
    try testing.expectEqualStrings("xml version=\"2.0\"", procinst.getValue());
}

test "NodeList.keys" {
  // TODO
}

test "NodeList.values" {
  // TODO
}

test "NodeList.item" {
  // TODO: Returns an item in the list by its index, or null if the index is out-of-bounds.

}

test "NodeList.entries" {
  // TODO not sure how to do the iterator
  // Returns an iterator, allowing code to go through all key/value pairs contained in the collection. (In this case, the keys are integers starting from 0 and the values are nodes.)
}

test "NamedNodeMap.getNamedItem" {
  // TODO
}

test "NamedNodeMap.setNamedItem" {
  // TODO
}

test "NamedNodeMap.removeNamedItem" {
  // TODO
}

test "NamedNodeMap.length" {
  // TODO
}

test "NamedNodeMap.item" {
  // TODO Returns the Attr at the given index, or null if the index is higher or equal to the number of nodes.
}

test "NamedNodeMap.keys" {
  // TODO
}

test "NamedNodeMap.values" {
  // TODO
}
