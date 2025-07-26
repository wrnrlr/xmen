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

    pub fn setParentElement(self: Node, parent:*Node) void {
        switch (self) {
            .document => null,
            .element => |elem| elem.parentElement = parent,
            .text => |text| text.parentElement = parent,
            .attribute => |attr| attr.parentElement = parent
        }
    }

    pub fn getParentElement(self: Node) ?*Node {
        return switch (self) {
            .document => null,
            .element => self.element.parentElement,
            .text => self.text.parentElement,
            .attribute => self.attribute.parentElement,
        };
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

    pub fn appendChild(self: *Document, node: *Node, child: *Node) !*Node {
        switch (child.*) {
            .document => {},
            .element => |e| e.parentElement = node,
            .attribute => |a| a.parentElement = node,
            .text => {}
        }
        try self.children.append(child.*);
        return child;
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
    attributes: std.ArrayList(Node) = undefined,
    children: std.ArrayList(Node) = undefined,
    parentElement: ?*Node = null,

  pub fn init(allocator: Allocator, tagName: []const u8) Element {
      return Element{
          .tagName = tagName,
          .attributes = std.ArrayList(Node).init(allocator),
          .children = std.ArrayList(Node).init(allocator),
          .parentElement = null,
      };
  }

  pub fn deinit(self: *Element) void {
      self.attributes.deinit();
      self.children.deinit();
  }

  pub fn appendChild(self: *Element, node: *Node, child: *Node) !*Node {
      switch (child.*) {
          .document => {},
          .element => |e| e.parentElement = node,
          .attribute => |a| a.parentElement = node,
          .text => {}
      }

      try self.children.append(child.*);
      return child;
  }

  pub fn getAttribute(self: *Element, name: []const u8) ?*Attr {
      for (self.attributes.items) |node| {
          switch (node) {
              .attribute => |attr| {
                  if (std.mem.eql(u8, attr.name, name)) return attr;
              },
              else => {}
          }
      }
      return null;
  }

  pub fn setAttribute(self: *Element, node: *Node, attr: *Attr) !void {
      for (self.attributes.items) |*existingAttr| {
          switch (existingAttr.*) {
              .attribute => |attrInner| {
                  if (std.mem.eql(u8, attrInner.name, attr.name)) {
                      existingAttr.* = Node{ .attribute = &attr.* };
                      return;
                  }
              },
              else => {},
          }
      }
      attr.parentElement = node;
      try self.attributes.append(Node{ .attribute = attr });
  }

  pub fn deleteAttribute(self: *Element, name: []const u8, value: []const u8) !void {
      for (self.attributes.items, 0..) |item, index| {
          if (item == .attribute) {
              if (std.mem.eql(u8, item.attribute.name, name) and std.mem.eql(u8, item.attribute.value, value)) {
                  _ = self.attributes.swapRemove(index);
                  return;
              }
          }
      }
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
    parentElement: ?*Node = null,

    fn render(self: Text, writer: anytype) RenderError!void {
        try writer.print("{s}", .{self.content});
    }
};

pub const Attr = struct {
    nodeType: NodeType = .attribute,
    name: []const u8,
    value: []const u8,
    parentElement: ?*Node = null,

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

test "Node.parentElement returns parent" {
    var doc = Document.init(testing.allocator);
    var elem = Element.init(testing.allocator, "div");
    var text = Text{ .content = "Hello" };
    var attr = Attr{ .name = "id", .value = "test" };

    var doc_node = Node{ .document = &doc };
    try testing.expectEqual(null, doc_node.getParentElement());

    var elem_node = Node{ .element = &elem };
    try testing.expectEqual(null, elem_node.getParentElement());

    elem_node.element.parentElement = &doc_node;
    try testing.expectEqual(&doc_node, elem_node.getParentElement());

    var text_node = Node{ .text = &text };
    try testing.expectEqual(null, text_node.getParentElement());

    text_node.text.parentElement = &elem_node;
    try testing.expectEqual(&elem_node, text_node.getParentElement());

    var attr_node = Node{ .attribute = &attr };
    try testing.expectEqual(null, attr_node.getParentElement());

    attr_node.attribute.parentElement = &elem_node;
    try testing.expectEqual(&elem_node, attr_node.getParentElement());
}

test "Element.init creates element with correct properties" {
    const elem = Element.init(testing.allocator, "div");
    try testing.expectEqualStrings("div", elem.tagName);
    try testing.expectEqual(NodeType.element, elem.nodeType);
    try testing.expectEqual(@as(usize, 0), elem.attributes.items.len);
    try testing.expectEqual(@as(usize, 0), elem.children.items.len);
    try testing.expectEqual(@as(?*Node, null), elem.parentElement);
}

test "Element.setAttribute and getAttribute work correctly" {
    var elem = Element.init(testing.allocator, "div");
    // This line should now work with the updated signature; no change needed, but confirming for context
    var elemNode = Node{ .element = &elem };
    const newAttrId = try testing.allocator.create(Attr);
    newAttrId.* = Attr{ .name = "id", .value = "test", .parentElement = &elemNode };
    try elem.setAttribute(&elemNode, newAttrId);
    const newAttrClass = try testing.allocator.create(Attr);
    newAttrClass.* = Attr{ .name = "class", .value = "container", .parentElement = &elemNode };
    try elem.setAttribute(&elemNode, newAttrClass);

    try testing.expectEqualStrings("test", elem.getAttribute("id").?.value);
    try testing.expectEqualStrings("container", elem.getAttribute("class").?.value);
    try testing.expectEqual(@as(?*Attr, null), elem.getAttribute("style"));
    const newAttrNewId = try testing.allocator.create(Attr);
    newAttrNewId.* = Attr{ .name = "id", .value = "new-id", .parentElement = &elemNode };
    try elem.setAttribute(&elemNode, newAttrNewId);
    try testing.expectEqualStrings("new-id", elem.getAttribute("id").?.value);
    try testing.expectEqual(@as(usize, 2), elem.attributes.items.len);
    testing.allocator.destroy(newAttrId);
    testing.allocator.destroy(newAttrClass);
    testing.allocator.destroy(newAttrNewId);
    elem.deinit();
}

// test "Element.appendChild sets parent and adds child" {
//     var parent = Element.init(testing.allocator, "div");
//     var child_elem = Element.init(testing.allocator, "span");
//     var text = Text{ .content = "Hello" };

//     var parent_node = Node{ .element = &parent };
//     var child_node = Node{ .element = &child_elem };
//     var text_node = Node{ .text = &text };

//     _ = try parent.appendChild(&parent_node, &child_node);
//     try testing.expectEqual(@as(usize, 1), parent.children.items.len);
//     try testing.expectEqual(&parent_node, child_elem.parentElement);

//     _ = try child_elem.appendChild(&child_node, &text_node);
//     try testing.expectEqual(@as(usize, 1), parent.children.items.len);
//     try testing.expectEqual(&child_node, text.parentElement);
//     parent.deinit();
//     child_elem.deinit();
// }

test "Render simple element with attributes and text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var elem = Element.init(allocator, "div");
    var elemNode = Node{ .element = &elem };
    const newAttrId = try testing.allocator.create(Attr);
    newAttrId.* = Attr{ .name = "id", .value = "test", .parentElement = &elemNode };
    try elem.setAttribute(&elemNode, newAttrId);
    var text = Text{ .content = "Hello, World!" };
    var text_node = Node{ .text = &text };
    _ = try elem.appendChild(&elemNode, &text_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try elem.render(buffer.writer());

    const expected = "<div id=\"test\">Hello, World!</div>";
    try testing.expectEqualStrings(expected, buffer.items);
    testing.allocator.destroy(newAttrId);
}

test "Render nested elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parent = Element.init(allocator, "div");
    var parentNode = Node{ .element = &parent };
    const newAttrClass = try testing.allocator.create(Attr);
    newAttrClass.* = Attr{ .name = "class", .value = "container", .parentElement = &parentNode };
    try parent.setAttribute(&parentNode, newAttrClass);

    var child = Element.init(allocator, "span");
    var text = Text{ .content = "Nested" };
    var text_node = Node{ .text = &text };
    var child_node = Node{ .element = &child };

    _ = try child.appendChild(&child_node, &text_node);
    _ = try parent.appendChild(&parentNode, &child_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try parent.render(buffer.writer());

    const expected = "<div class=\"container\"><span>Nested</span></div>";
    try testing.expectEqualStrings(expected, buffer.items);
    testing.allocator.destroy(newAttrClass);
}

test "Document renders children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var doc = Document.init(allocator);
    var doc_node = Node{ .document = &doc };
    var elem = Element.init(allocator, "p");
    var text = Text{ .content = "Document content" };
    var text_node = Node{ .text = &text };
    var elem_node = Node{ .element = &elem };

    _ = try elem.appendChild(&elem_node, &text_node);
    _ = try doc.appendChild(&doc_node, &elem_node);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try doc.render(buffer.writer());

    const expected = "<p>Document content</p>";
    try testing.expectEqualStrings(expected, buffer.items);
}

// test "Element.deleteAttribute removes attribute correctly" {
//     var elem = Element.init(testing.allocator, "div");
//     var elemNode = Node{ .element = &elem };
//     const newAttr = try testing.allocator.create(Attr);
//     newAttr.* = Attr{ .name = "id", .value = "old-id", .parentElement = &elemNode };
//     try elem.setAttribute(&elemNode, newAttr);

//     try testing.expectEqual(@as(usize, 3), elem.attributes.items.len);  // Initial count

//     try elem.deleteAttribute("id", "old-id");  // Delete specific one

//     try testing.expectEqual(@as(usize, 2), elem.attributes.items.len);  // Should have removed one
//     try testing.expect( elem.getAttribute("id") != null );  // The other "id" should still be there
//     try testing.expectEqualStrings("container", elem.getAttribute("class").?.value);

//     testing.allocator.destroy(newAttr);
//     elem.deinit();
// }
