const std = @import("std");

const Allocator = std.mem.Allocator;
const WriteError = std.fs.File.WriteError;
const RenderError = WriteError || error{OutOfMemory};

pub const NodeType = enum(u8) {
    element = 1,
    attribute = 2,
    text = 3,
    cdata = 4,
    processing_instruction = 7,
    comment = 8,
    document = 9,
};

const InternalType = enum(u8) {
    element = 1,
    attribute = 2,
    text = 3,
    document = 9,
};

pub const Node = union(InternalType) {
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

    pub fn appendChild(self: Node, child: *Node) !*Node {
      return switch (self) {
          .document => |doc| doc.appendChild(@constCast(&self), child),
          .element => |elem| elem.appendChild(@constCast(&self), child),
          else => @panic("oops")
      };
    }

    pub fn setAttributeNode(node: Node, attr: *Node) void {
      switch (node) {
          .element => |elem| elem.setAttributeNode(node, attr),
          else => @panic("oops")
      }
    }

    pub fn setParentElement(self: Node, parent: *Node) void {
        switch (self) {
            .element => |elem| elem.parentElement = parent,
            .attribute => |attr| attr.parentElement = parent,
            .text => |text| text.parentElement = parent,
            .document => null,
        }
    }

    pub fn getParentElement(self: Node) ?*Node {
        return switch (self) {
            .element => |elem| elem.parentElement,
            .attribute => |attr| attr.parentElement,
            .text => |text| text.parentElement,
            .document => null,
        };
    }

    pub fn getNodeType(self: Node) NodeType {
        return switch (self) {
            .document => NodeType.document,
            .element => NodeType.element,
            .text => self.text.nodeType,
            .attribute => NodeType.attribute,
        };
    }

    pub fn render(self: Node, writer: anytype) RenderError!void {
        switch (self) {
            .document => |doc| try doc.render(writer),
            .element => |elem| try elem.render(writer),
            .text => |text| try text.render(writer),
            .attribute => |attr| try attr.render(writer),
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

    pub fn setNamedItem(self: NamedNodeMap, attr: *Node) !void {
        std.debug.assert(attr.* == .attribute);
        return self.node.element.setAttributeNode(self.node, attr) catch {};
    }

    pub fn removeNamedItem(self: NamedNodeMap, name: []u8) void {
      self.node.element.removeAttribute(name) catch {};
    }

    pub fn length() i32 { return 0; }
    // iter
    // render
};

pub const Attr = struct {
    name: []const u8,
    value: []const u8,
    parentElement: ?*Node = null,

    pub fn init(name: []const u8, value: []const u8, parentElement: ?*Node) Attr {
      return Attr{ .name = name, .value = value, .parentElement = parentElement};
    }

    fn render(self: Attr, writer: anytype) RenderError!void {
        try writer.print(" {s}=\"{s}\"", .{ self.name, self.value });
    }
};

pub const Text = struct {
    nodeType: NodeType,
    content: []const u8,
    parentElement: ?*Node = null,

    pub fn text(content: []const u8, parent: ?*Node) Text {
      return Text{ .nodeType = NodeType.text, .content = content, .parentElement = parent };
    }

    pub fn cdata(content: []const u8, parent: ?*Node) Text {
      return Text{ .nodeType = NodeType.cdata, .content = content, .parentElement = parent };
    }

    pub fn instruction(content: []const u8, parent: ?*Node) Text {
      return Text{ .nodeType = NodeType.processing_instruction, .content = content, .parentElement = parent };
    }

    pub fn comment(content: []const u8, parent: ?*Node) Text {
      return Text{ .nodeType = NodeType.comment, .content = content, .parentElement = parent };
    }

    fn render(self: Text, writer: anytype) RenderError!void {
        try switch (self.nodeType) {
          NodeType.cdata => self.render_cdata(writer),
          NodeType.comment => self.render_cdata(writer),
          NodeType.processing_instruction => self.render_instruction(writer),
          NodeType.text => self.render_text(writer),
          else => {}
        };
    }

    fn render_text(self: Text, writer: anytype) RenderError!void {
      try writer.print("{s}", .{self.content});
    }

    fn render_instruction(self: Text, writer: anytype) RenderError!void {
      try writer.print("<?{s}?>", .{self.content});
    }

    fn render_comment(self: Text, writer: anytype) RenderError!void {
      try writer.print("<!--{s}-->", .{self.content});
    }

    fn render_cdata(self: Text, writer: anytype) RenderError!void {
      try writer.print("<![CDATA[{s}]]>", .{self.content});
    }
};

const testing = std.testing;

test "Node.getNodeType" {
    var doc = Node{ .document = @constCast(&Document.init(testing.allocator)) };
    try testing.expectEqual(NodeType.document, doc.getNodeType());

    var elem = Node{ .element = @constCast(&Element.init(testing.allocator, "div")) };
    try testing.expectEqual(NodeType.element, elem.getNodeType());

    var attr = Node{ .attribute = @constCast(&Attr{ .name = "id", .value = "test" }) };
    try testing.expectEqual(NodeType.attribute, attr.getNodeType());

    var cdata = Node{ .text = @constCast(&Text.cdata("cdata", null)) };
    try testing.expectEqual(NodeType.cdata, cdata.getNodeType());

    var comment = Node{ .text = @constCast(&Text.comment("comment", null)) };
    try testing.expectEqual(NodeType.comment, comment.getNodeType());

    var text = Node{ .text = @constCast(&Text.text("text", null)) };
    try testing.expectEqual(NodeType.text, text.getNodeType());

    var instruction = Node{ .text = @constCast(&Text.instruction("instruction", null)) };
    try testing.expectEqual(NodeType.processing_instruction, instruction.getNodeType());
}

test "Node.parentElement" {
    var doc = Node{ .document = @constCast(&Document.init(testing.allocator)) };
    try testing.expectEqual(null, doc.getParentElement());

    var elem = Node{ .element = @constCast(&Element.init(testing.allocator, "div")) };
    try testing.expectEqual(null, elem.getParentElement());

    elem.element.parentElement = &doc;
    try testing.expectEqual(&doc, elem.getParentElement());

    var text = Node{ .text = @constCast(&Text.text("Hi", null)) };
    try testing.expectEqual(null, text.getParentElement());

    text.text.parentElement = &elem;
    try testing.expectEqual(&elem, text.getParentElement());

    var attr = Node{ .attribute = @constCast(&Attr{ .name = "id", .value = "test" }) };
    try testing.expectEqual(null, attr.getParentElement());

    attr.attribute.parentElement = &elem;
    try testing.expectEqual(&elem, attr.getParentElement());
}

test "Node.render" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var elem = Node{ .element = @constCast(&Element.init(allocator, "p")) };
    const attr = Node{ .attribute = @constCast(&Attr.init("id", "1", &elem)) };
    try elem.element.setAttributeNode(&elem, @constCast(&attr));

    var a = Node{ .element = @constCast(&Element.init(allocator, "a")) };
    var text = Node{ .text = @constCast(&Text.text("Hi", &a)) };

    // var doc = Node{ .document = @constCast(&Document.init(allocator)) };
    // _ = try doc.document.appendChild(&doc, &elem);

    _ = try a.appendChild(&text);
    _ = try elem.appendChild(&a);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try elem.render(buffer.writer());

    try testing.expectEqualStrings("<p id=\"1\"><a>Hi</a></p>", buffer.items);

    elem.deinit();
    attr.deinit();
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
    var elem = Node{ .element = @constCast(&Element.init(testing.allocator, "a")) };
    const id = Node{ .attribute = @constCast(&Attr.init("id", "1", &elem)) };
    try elem.element.setAttributeNode(&elem, @constCast(&id));
    const class = Node{ .attribute = @constCast(&Attr.init("class", "a", &elem )) };
    try elem.element.setAttributeNode(&elem, @constCast(&class));

    try testing.expectEqualStrings("1", elem.element.getAttributeNode("id").?.attribute.value);
    try testing.expectEqualStrings("a", elem.element.getAttributeNode("class").?.attribute.value);
    try testing.expectEqual(@as(?*Node, null), elem.element.getAttributeNode("style"));
    try testing.expectEqual(@as(usize, 2), elem.element.attributes.items.len);

    id.attribute.value = "2";
    try elem.element.setAttributeNode(&elem, @constCast(&id));
    try testing.expectEqualStrings("2", elem.element.getAttributeNode("id").?.attribute.value);

    id.deinit();
    class.deinit();
    elem.deinit();
}

test "Element.removeAttribute" {
    var elem = Node{ .element = @constCast(&Element.init(testing.allocator, "a")) };
    const id = Node{ .attribute = @constCast(&Attr.init("id", "1", &elem)) };

    try elem.element.setAttributeNode(&elem, @constCast(&id));
    try elem.element.removeAttribute("id");

    try testing.expectEqual(@as(?*Node, null), elem.element.getAttributeNode("id"));

    id.deinit();
    elem.deinit();
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

test "NamedNodeMap.init" {
    const allocator = testing.allocator;
    var elem = Node{ .element = @constCast(&Element.init(allocator, "div")) };
    var items = std.ArrayList(Node).init(allocator);
    const namedNodeMap = NamedNodeMap.init(&elem, items);
    try testing.expectEqual(.element, namedNodeMap.node.*.element.nodeType);
    items.deinit();
}

test "NamedNodeList.getNamedItem" {
    const allocator = testing.allocator;
    var elem = Node{ .element = @constCast(&Element.init(allocator, "div")) };
    var items = std.ArrayList(Node).init(allocator);
    var namedNodeMap = NamedNodeMap.init(&elem, items);
    var attr = Node{ .attribute = @constCast(&Attr.init("id", "test", &elem)) };
    _ = namedNodeMap.setNamedItem(&attr) catch {};
    const item = namedNodeMap.getNamedItem(@constCast("id"));
    try testing.expect(item != null);
    try testing.expectEqualStrings("test", item.?.attribute.value);
    elem.deinit();
    attr.deinit();
    items.deinit();
}

test "NamedNodeMap.setNamedItem" {
    const allocator = testing.allocator;
    var elem = Node{ .element = @constCast(&Element.init(allocator, "div")) };
    var items = std.ArrayList(Node).init(allocator);
    var namedNodeMap = NamedNodeMap.init(&elem, items);
    var attr = Node{ .attribute = @constCast(&Attr.init("id", "test", &elem)) };
    try elem.element.setAttributeNode(&elem, @constCast(&attr));
    const item = namedNodeMap.getNamedItem(@constCast("id"));
    try testing.expect(item != null);
    try testing.expectEqualStrings("test", item.?.attribute.value);
    elem.deinit();
    attr.deinit();
    items.deinit();
}

test "NamedNodeMap.removeNamedItem" {
    const allocator = testing.allocator;
    var elem = Node{ .element = @constCast(&Element.init(allocator, "div")) };
    var items = std.ArrayList(Node).init(allocator);
    var namedNodeMap = NamedNodeMap.init(&elem, items);
    var attr = Node{ .attribute = @constCast(&Attr.init("id", "test", &elem)) };
    namedNodeMap.setNamedItem(&attr) catch {};
    namedNodeMap.removeNamedItem(@constCast("id"));
    const item = namedNodeMap.getNamedItem(@constCast("id"));
    try testing.expect(item == null);
    elem.deinit();
    attr.deinit();
    items.deinit();
}

test "NamedNodeMap.length" {

}

test "Attr.init" {

}
