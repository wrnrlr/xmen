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
    children: std.ArrayList(*Node),

    pub fn init(allocator: Allocator) Document {
        return Document{
            .children = std.ArrayList(*Node).init(allocator),
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
        try self.children.append(child);
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
    attributes: std.ArrayList(*Node) = undefined,
    children: std.ArrayList(*Node) = undefined,
    parentElement: ?*Node = null,

  pub fn init(allocator: Allocator, tagName: []const u8) Element {
      return Element{
          .tagName = tagName,
          .attributes = std.ArrayList(*Node).init(allocator),
          .children = std.ArrayList(*Node).init(allocator),
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

      try self.children.append(child);
      return child;
  }

  pub fn getAttributeNode(self: *Element, name: []const u8) ?*Node {
      for (self.attributes.items) |node|
          if (std.mem.eql(u8, node.attribute.name, name)) return node;
      return null;
  }

  pub fn setAttributeNode(self: *Element, elem: *Node, attr: *Node) !void {
      std.debug.assert(elem.* == .element);
      std.debug.assert(attr.* == .attribute);

      for (self.attributes.items) |*item| {
          switch (item.*.*) {
              .attribute => {
                  const a = item.*.attribute;
                  if (std.mem.eql(u8, a.name, attr.attribute.name)) {
                      a.value = attr.attribute.value;
                      return;
                  }
              },
              else => {},
          }
      }

      attr.attribute.parentElement = elem;
      try self.attributes.append(attr);
  }

  pub fn removeAttribute(self: *Element, name: []const u8) !void {
      for (self.attributes.items, 0..) |item, index| {
          if (std.mem.eql(u8, item.attribute.name, name)) {
              _ = self.attributes.swapRemove(index);
              return;
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

pub const NamedNodeMap = struct {
    node: *Node,
    items: std.ArrayList(Node) = undefined,

    pub fn init(node: *Node, items: std.ArrayList(Node)) NamedNodeMap {
        std.debug.assert(node.* == .element);
        return NamedNodeMap{ .node = node, .items = items };
    }

    pub fn getNamedItem(self: NamedNodeMap, name: []u8) ?*Node {
        return self.node.element.getAttributeNode(name);
    }

    pub fn setNamedItem(self: NamedNodeMap, attr: *Node) void {
        std.debug.assert(attr.* == .attribute);
        return self.node.element.setAttributeNode(self.node, attr);
    }

    pub fn removeNamedItem(self: NamedNodeMap, name: []u8) void {
      self.node.element.removeAttribute(name);
    }

    pub fn length() i32 { return 0; }
    // iter
    // render
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

test "Node.getNodeType" {
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

test "Node.parentElement" {
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

test "Element.init" {
    const elem = Element.init(testing.allocator, "div");
    try testing.expectEqualStrings("div", elem.tagName);
    try testing.expectEqual(NodeType.element, elem.nodeType);
    try testing.expectEqual(@as(usize, 0), elem.attributes.items.len);
    try testing.expectEqual(@as(usize, 0), elem.children.items.len);
    try testing.expectEqual(@as(?*Node, null), elem.parentElement);
}

test "Element.{set|get}Attribute" {
    var elem = Element.init(testing.allocator, "div");
    // This line should now work with the updated signature; no change needed, but confirming for context
    var elemNode = Node{ .element = &elem };
    const newAttrId = try testing.allocator.create(Attr);
    newAttrId.* = Attr{ .name = "id", .value = "test", .parentElement = &elemNode };
    const attrNode = Node{ .attribute = newAttrId };
    try elem.setAttributeNode(&elemNode, @constCast(&attrNode));
    const newAttrClass = try testing.allocator.create(Attr);
    newAttrClass.* = Attr{ .name = "class", .value = "container", .parentElement = &elemNode };
    const attrNode2 = Node{ .attribute = newAttrClass };
    try elem.setAttributeNode(&elemNode, @constCast(&attrNode2));

    try testing.expectEqualStrings("test", elem.getAttributeNode("id").?.attribute.value);
    try testing.expectEqualStrings("container", elem.getAttributeNode("class").?.attribute.value);
    try testing.expectEqual(@as(?*Node, null), elem.getAttributeNode("style"));
    const newAttrNewId = try testing.allocator.create(Attr);
    newAttrNewId.* = Attr{ .name = "id", .value = "new-id", .parentElement = &elemNode };
    var attrNode3 = Node{ .attribute = newAttrNewId };
    try elem.setAttributeNode(&elemNode, &attrNode3);
    try testing.expectEqualStrings("new-id", elem.getAttributeNode("id").?.attribute.value);
    try testing.expectEqual(@as(usize, 2), elem.attributes.items.len);
    testing.allocator.destroy(newAttrId);
    testing.allocator.destroy(newAttrClass);
    testing.allocator.destroy(newAttrNewId);
    elem.deinit();
}

test "Element.removeAttribute" {

}

test "Element.appendChild sets parent and adds child" {
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
}

test "NamedNodeList.init" {

}

test "NamedNodeList.getNamedItem" {

}

test "NamedNodeList.setNamedItem" {

}

test "NamedNodeList.removeNamedItem" {

}

test "NamedNodeList.length" {

}


test "Attr.init" {}


test "Render simple element with attributes and text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var elem = Element.init(allocator, "div");
    var elemNode = Node{ .element = &elem };
    const newAttrId = try testing.allocator.create(Attr);
    newAttrId.* = Attr{ .name = "id", .value = "test", .parentElement = &elemNode };
    var attrNode = Node{ .attribute = newAttrId };
    try elem.setAttributeNode(&elemNode, &attrNode);
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
    var attrNodeClass = Node{ .attribute = newAttrClass };
    try parent.setAttributeNode(&parentNode, &attrNodeClass);

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
