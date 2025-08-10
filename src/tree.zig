const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ArrayList = std.ArrayList;
pub const StringArrayHashMap = std.StringArrayHashMap;

const Element = struct {
    alloc: Allocator,
    name: [:0]const u8,
    attributes: *NamedNodeMap,
    children: *NodeList,
    parent: ?*Node = null,

    fn init(alloc: Allocator, tag: []const u8) !Element {
        const name = try alloc.dupeZ(u8, tag);
        const attrs = try alloc.create(NamedNodeMap);
        attrs.* = try NamedNodeMap.init(alloc);
        const kids = try alloc.create(NodeList);
        kids.* = NodeList.init(alloc);
        return .{ .alloc = alloc, .name = name, .attributes = attrs, .children = kids };
    }

    fn deinit(elem: *Element) void {
        elem.alloc.free(elem.name);
        elem.children.deinit();
        elem.alloc.destroy(elem.children);
        elem.attributes.deinit();
        elem.alloc.destroy(elem.attributes);
    }

    fn getAttribute(elem: *Element, name: [:0]const u8) ?*Node {
        return elem.attributes.getNamedItem(name);
    }

    fn setAttribute(elem: *Element, name: [:0]const u8, value: [:0]const u8) !void {
        defer elem.alloc.free(@constCast(name[0..name.len + 1]));
        defer elem.alloc.free(@constCast(value[0..value.len + 1]));
        if (elem.getAttribute(name)) |attr| {
            try attr.setValue(value);
        } else {
            const attr = try Node.Attr(elem.alloc, name, value);
            try elem.attributes.setNamedItem(attr);
        }
    }

    fn removeAttribute() void {
      // TODO
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

    fn setValue(attr: *Attribute, value: [:0]const u8) !void {
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

    fn setContent(char: *CharData, value: [:0]const u8) !void {
        char.alloc.free(char.content);
        char.content = try char.alloc.dupeZ(u8, value);
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

    fn deinit(doc: *Document) void {
        doc.children.deinit();
        doc.alloc.destroy(doc.children);
    }
};

pub const NodeList = struct {
  alloc: Allocator,
  list: ArrayList(*Node),

  fn init(alloc: Allocator) NodeList {
      return .{ .alloc = alloc, .list = ArrayList(*Node).init(alloc) };
  }

  fn deinit(self: *NodeList) void {
      for (self.list.items) |child| {
          child.deinit();
          self.alloc.destroy(child);
      }
      self.list.deinit();
  }

  fn item(self: *NodeList, index: usize) ?*Node {
      return if (index < self.list.items.len) self.list.items[index] else null;
  }

  fn append(self: *NodeList, node: *Node) !void {
      try self.list.append(node);
  }

  fn insert(self: *NodeList, index: usize, node: *Node) !void {
      try self.list.insert(index, node);
  }

  fn remove(self: *NodeList, discarded: *Node) void {
      for (self.list.items, 0..) |child, i| {
          if (child == discarded) {
              _ = self.list.orderedRemove(i);
              break;
          }
      }
  }

  fn length(self: *NodeList) usize {
      return self.list.items.len;
  }

  fn keys(self: *NodeList) []const usize {
      var indices = std.ArrayList(usize).init(self.alloc);
      defer indices.deinit();
      for (0..self.list.items.len) |i| {
          indices.append(i) catch return &.{};
      }
      return indices.toOwnedSlice() catch &.{};
  }

  fn values(self: *NodeList) []*Node {
      return self.list.items;
  }

  fn entries(self: *NodeList) []const struct { usize, *Node } {
      var result = std.ArrayList(struct { usize, *Node }).init(self.alloc);
      defer result.deinit();
      for (self.list.items, 0..) |node, i| {
          result.append(.{ i, node }) catch return &.{};
      }
      return result.toOwnedSlice() catch &.{};
  }
};

pub const NamedNodeMap = struct {
  alloc: Allocator,
  items: StringArrayHashMap(*Node),

  fn init(alloc: Allocator) !NamedNodeMap {
      return .{ .alloc = alloc, .items = StringArrayHashMap(*Node).init(alloc) };
  }

  fn deinit(self: *NamedNodeMap) void {
      for (self.items.values()) |value| {
          value.deinit();
          self.alloc.destroy(value);
      }
      self.items.deinit();
  }

  fn getNamedItem(self: *NamedNodeMap, name: [:0]const u8) ?*Node {
      return self.items.get(name);
  }

  fn setNamedItem(self: *NamedNodeMap, new: *Node) !void {
      std.debug.assert(new.* == .attribute);
      const attr = &new.attribute;

      if (self.items.get(attr.name)) |existing| {
          try existing.setValue(attr.value);
          new.deinit();
          self.alloc.destroy(new);
      } else {
          try self.items.put(attr.name, new);
      }
  }

  fn removeNamedItem(self: *NamedNodeMap, name: [:0]const u8) void {
      if (self.items.fetchOrderedRemove(name)) |kv| {
        kv.value.deinit();
        self.alloc.destroy(kv.value);
      }
  }

  fn length(self: *NamedNodeMap) usize {
      return self.items.count();
  }

  fn item(self: *NamedNodeMap, index: usize) ?*Node {
      if (index >= self.items.count()) return null;
      return self.values()[index];
  }

  fn keys(self: *NamedNodeMap) []const []const u8 {
      return self.items.keys();
  }

  fn values(self: *NamedNodeMap) []const *Node {
      return self.items.values();
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
            .element => |e| e.children.length(),
            .document => |d| d.children.length(),
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
                .element => |*e| e.children.remove(n),
                .document => |*d| d.children.remove(n),
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
            .element => |e| if (e.attributes.getNamedItem(name)) |attr| attr.getValue() else null,
            else => unreachable,
        };
    }

    pub fn setAttribute(n: *Node, name: []const u8, value: []const u8) !void {
        switch (n.*) {
            .element => |*e| try e.setAttribute(try e.alloc.dupeZ(u8, name), try e.alloc.dupeZ(u8, value)),
            else => unreachable,
        }
    }

    // Value Nodes: Attr, Text, CData, Comment, ProcInst
    pub fn setValue(n: *Node, value: [:0]const u8) !void {
        switch (n.*) {
            .attribute => |*a| try a.setValue(value),
            .text => |*t| try t.setContent(value),
            .cdata => |*c| try c.setContent(value),
            .comment => |*c| try c.setContent(value),
            .proc_inst => |*p| try p.setContent(value),
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

test "NodeList.item" {
    var list = NodeList.init(testing.allocator);
    defer list.deinit();

    const node1 = try Node.Elem(testing.allocator, "div");
    const node2 = try Node.Text(testing.allocator, "Hello");
    try list.append(node1);
    try list.append(node2);

    try testing.expectEqual(node1, list.item(0).?);
    try testing.expectEqual(node2, list.item(1).?);
    try testing.expectEqual(null, list.item(2));
}

test "NodeList.keys" {
    var list = NodeList.init(testing.allocator);
    defer list.deinit();

    const node1 = try Node.Elem(testing.allocator, "div");
    const node2 = try Node.Text(testing.allocator, "Hello");
    try list.append(node1);
    try list.append(node2);

    const keys = list.keys();
    defer testing.allocator.free(keys);
    try testing.expectEqualSlices(usize, &[_]usize{ 0, 1 }, keys);
}

test "NodeList.values" {
    var list = NodeList.init(testing.allocator);
    defer list.deinit();

    const node1 = try Node.Elem(testing.allocator, "div");
    const node2 = try Node.Text(testing.allocator, "Hello");
    try list.append(node1);
    try list.append(node2);

    const values = list.values();
    try testing.expectEqualSlices(*Node, &[_]*Node{ node1, node2 }, values);
}

test "NodeList.entries" {
    var list = NodeList.init(testing.allocator);
    defer list.deinit();

    const node1 = try Node.Elem(testing.allocator, "div");
    const node2 = try Node.Text(testing.allocator, "Hello");
    try list.append(node1);
    try list.append(node2);

    const entries = list.entries();
    defer testing.allocator.free(entries);
    try testing.expectEqual(2, entries.len);
    try testing.expectEqual(0, entries[0][0]);
    try testing.expectEqual(node1, entries[0][1]);
    try testing.expectEqual(1, entries[1][0]);
    try testing.expectEqual(node2, entries[1][1]);
}

test "NamedNodeMap.getNamedItem" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    const attr2 = try Node.Attr(testing.allocator, "class", "container");
    try map.setNamedItem(attr1);
    try map.setNamedItem(attr2);

    try testing.expectEqual(attr1, map.getNamedItem("id").?);
    try testing.expectEqual(attr2, map.getNamedItem("class").?);
    try testing.expectEqual(null, map.getNamedItem("style"));
}

test "NamedNodeMap.setNamedItem" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    try map.setNamedItem(attr1);
    try testing.expectEqualStrings("main", map.getNamedItem("id").?.getValue());

    const attr2 = try Node.Attr(testing.allocator, "id", "content");
    try map.setNamedItem(attr2);
    try testing.expectEqualStrings("content", map.getNamedItem("id").?.getValue());
}

test "NamedNodeMap.removeNamedItem" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr = try Node.Attr(testing.allocator, "id", "main");
    try map.setNamedItem(attr);
    try testing.expectEqual(1, map.length());

    map.removeNamedItem("id");
    try testing.expectEqual(0, map.length());
    try testing.expectEqual(null, map.getNamedItem("id"));
}

test "NamedNodeMap.length" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    try testing.expectEqual(0, map.length());

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    const attr2 = try Node.Attr(testing.allocator, "class", "container");
    try map.setNamedItem(attr1);
    try map.setNamedItem(attr2);

    try testing.expectEqual(2, map.length());
}

test "NamedNodeMap.item" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    const attr2 = try Node.Attr(testing.allocator, "class", "container");
    try map.setNamedItem(attr1);
    try map.setNamedItem(attr2);

    // Order is not guaranteed in hash map, so we check presence
    const item0 = map.item(0).?;
    const item1 = map.item(1).?;
    try testing.expect((item0 == attr1 and item1 == attr2) or (item0 == attr2 and item1 == attr1));
    try testing.expectEqual(null, map.item(2));
}

test "NamedNodeMap.keys" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    const attr2 = try Node.Attr(testing.allocator, "class", "container");
    try map.setNamedItem(attr1);
    try map.setNamedItem(attr2);

    const keys = map.keys();
    try testing.expectEqual(2, keys.len);
    // try testing.expect(std.mem.indexOfScalar([]const u8, keys, "id") != null);
    // try testing.expect(std.mem.indexOfScalar([]const u8, keys, "class") != null);
}

test "NamedNodeMap.values" {
    var map = try NamedNodeMap.init(testing.allocator);
    defer map.deinit();

    const attr1 = try Node.Attr(testing.allocator, "id", "main");
    const attr2 = try Node.Attr(testing.allocator, "class", "container");
    try map.setNamedItem(attr1);
    try map.setNamedItem(attr2);

    const values = map.values();
    try testing.expectEqual(2, values.len);
    try testing.expect(std.mem.indexOfScalar(*Node, values, attr1) != null);
    try testing.expect(std.mem.indexOfScalar(*Node, values, attr2) != null);
}
