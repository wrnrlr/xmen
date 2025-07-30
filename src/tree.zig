const std = @import("std");

const Allocator = std.mem.Allocator;

pub const NodeList = std.ArrayList(*Node);
pub const NamedNodeMap = std.AutoArrayHashMap([]const u8, []const u8);

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
    element: struct {
        alloc: Allocator,
        name: [:0]const u8,
        attributes: *NamedNodeMap = undefined,
        children: *NodeList = undefined,
        parent: ?*Node = null
    },
    attribute: struct {
        name: [:0]const u8,
        value: [*]const u8,
        parent: ?*Node = null
    },
    text: struct {
        content: [*]const u8,
        parent: ?*Node = null
    },
    cdata: struct {
        content: [*]const u8,
        parent: ?*Node = null
    },
    proc_inst: struct {
        content: [*]const u8,
        parent: ?*Node = null
    },
    comment: struct {
        content: [*]const u8,
        parent: ?*Node = null
    },
    document: struct {
        alloc: Allocator,
        children: *NodeList = undefined,
    },

    // Constructors

    pub fn Elem(alloc: Allocator, tag: []const u8) !Node {
        const name = try alloc.dupeZ(u8, tag); // Returns [:0]u8
        const attrs = try alloc.create(NamedNodeMap);
        attrs.* = NamedNodeMap.init(alloc);
        const kids = try alloc.create(NodeList);
        kids.* = NodeList.init(alloc);
        return Node{ .element = .{ .alloc = alloc, .name = name, .attributes = attrs, .children = kids } };
    }

    pub fn Attr(alloc: Allocator, name: []const u8, value: []const u8) !Node {
        const name_copy = try alloc.dupeZ(u8, name); // Returns [:0]u8
        const value_slice = try alloc.dupeZ(u8, value); // Allocate and copy value
        const value_copy: [*]const u8 = @ptrCast(value_slice); // Convert [:0]u8 to [*]const u8
        return Node{ .attribute = .{ .name = name_copy, .value = value_copy } };
    }

    pub fn Text(alloc: Allocator, content: []const u8) !Node {
        const content_slice = try alloc.dupeZ(u8, content); // Allocate and copy value
        const content_copy: [*]const u8 = @ptrCast(content_slice); // Convert [:0]u8 to [*]const u8
        return Node{ .text = .{ .content = content_copy } };
    }

    pub fn CData(alloc: Allocator, content: []const u8) !Node {
        const content_slice = try alloc.dupeZ(u8, content); // Allocate and copy value
        const content_copy: [*]const u8 = @ptrCast(content_slice); // Convert [:0]u8 to [*]const u8
        return Node{ .cdata = .{ .content = content_copy } };
    }

    pub fn ProcInst(alloc: Allocator, content: []const u8) !Node {
        const content_slice = try alloc.dupeZ(u8, content); // Allocate and copy value
        const content_copy: [*]const u8 = @ptrCast(content_slice); // Convert [:0]u8 to [*]const u8
        return Node{ .proc_inst = .{ .content = content_copy } };
    }

    pub fn Comment(alloc: Allocator, content: []const u8) !Node {
        const content_slice = try alloc.dupeZ(u8, content); // Allocate and copy value
        const content_copy: [*]const u8 = @ptrCast(content_slice); // Convert [:0]u8 to [*]const u8
        return Node{ .comment = .{ .content = content_copy } };
    }

    pub fn Doc(alloc: Allocator) !Node {
        const kids = try alloc.create(NodeList);
        kids.* = NodeList.init(alloc);
        return Node{ .document = .{ .alloc = alloc, .children = kids } };
    }

    // Node methods

    pub fn archetype(n:Node) NodeType {
        return switch (n) {
            .element => NodeType.element,
            .attribute => NodeType.attribute,
            .text => NodeType.text,
            .cdata => NodeType.cdata,
            .proc_inst => NodeType.proc_inst,
            .comment => NodeType.comment,
            .document => NodeType.document,
        };
    }

    pub fn parent(n: Node) ?*Node {
        return switch (n) {
            .element => |e| e.parent,
            .attribute => |a| a.parent,
            .text => |t| t.parent,
            .cdata => |t| t.parent,
            .proc_inst => |t| t.parent,
            .comment => |t| t.parent,
            .document => null,
        };
    }

    pub fn deinit(n: *Node) void {
        switch (n.*) {
            .element => |*e| {
                e.alloc.free(e.name); // Free [:0]const u8
                e.attributes.deinit();
                for (e.children.items) |child| {
                    child.deinit();
                    e.alloc.destroy(child); // Free the child pointer
                }
                e.children.deinit();
                e.alloc.destroy(e.children); // Free the NodeList pointer
            },
            .attribute => |*a| {
                if (a.parent) |p| {
                    switch (p.*) {
                        .element => |e| {
                            e.alloc.free(a.name); // Free [:0]const u8
                            e.alloc.free(a.value); // Free [*]const u8
                        },
                        .document => |d| {
                            d.alloc.free(a.name); // Free [:0]const u8
                            d.alloc.free(a.value); // Free [*]const u8
                        },
                        else => unreachable,
                    }
                }
            },
            .text => |*t| {
                if (t.parent) |p| {
                    switch (p.*) {
                        .element => |e| e.alloc.free(t.content),
                        .document => |d| d.alloc.free(t.content),
                        else => unreachable,
                    }
                }
            },
            .cdata => |*c| {
                if (c.parent) |p| {
                    switch (p.*) {
                        .element => |e| e.alloc.free(c.content),
                        .document => |d| d.alloc.free(c.content),
                        else => unreachable,
                    }
                }
            },
            .comment => |*c| {
                if (c.parent) |p| {
                    switch (p.*) {
                        .element => |e| e.alloc.free(c.content),
                        .document => |d| d.alloc.free(c.content),
                        else => unreachable,
                    }
                }
            },
            .proc_inst => |*p| {
                if (p.parent) |p_parent| {
                    switch (p_parent.*) {
                        .element => |e| e.alloc.free(p.content),
                        .document => |d| d.alloc.free(p.content),
                        else => unreachable,
                    }
                }
            },
            .document => |*d| {
                for (d.children.items) |child| {
                    child.deinit();
                    d.alloc.destroy(child); // Free the child pointer
                }
                d.children.deinit();
                d.alloc.destroy(d.children); // Free the NodeList pointer
            },
        }
    }


    // Inner nodes: Elem & Doc

    pub fn children(n: Node) *NodeList {
        std.debug.assert(n.* == .element or n.* == .document);
        return switch(n) {
          .element => |e| e.children,
          .document => |d| d.children,
          else => {}
        };
    }

    pub fn append(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .proc_inst);
        child.parent = n; // Set parent reference
        switch (n.*) {
            .element => |*e| try e.children.append(child),
            .document => |*d| try d.children.append(child),
            else => unreachable,
        }
    }

    pub fn prepend(n: *Node, child: *Node) !void {
        std.debug.assert(n.* == .element or n.* == .document);
        std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .proc_inst);
        child.parent = n; // Set parent reference
        switch (n.*) {
            .element => |*e| try e.children.prepend(child),
            .document => |*d| try d.children.prepend(child),
            else => unreachable,
        }
    }

    // Named nodes: Elem & Attr

    pub fn getName(n: Node) []const u8 {
      std.debug.assert(n == .element or n == .attribute);
      return switch (n) {
        .element => |e|  std.mem.span(e.name),
        .attribute => |a| std.mem.span(a.name),
        else => unreachable
      };
    }

    // Elem

    pub fn attributes(n: Node) *NamedNodeMap {
      std.debug.assert(n.* == .element);
      return switch(n) {
        .element => |e| e.attributes,
        else => unreachable
      };
    }

    // Value Nodes:  Attr, Text, CData, Comment, ProcInst

    pub fn setValue(n: Node, value: [*]const u8) void {
      std.debug.assert(n.* == .attribute or n.* == .text or n.* == .cdata or n.* == .comment or n.* == .proc_inst);
      switch (n.*) {
          .attribute => |*a| a.value = value,
          .text => |*t| t.content = value,
          .cdata => |*c| c.content = value,
          .comment => |*c| c.content = value,
          .proc_inst => |*p| p.content = value,
          else => unreachable
      }
    }

    pub fn getValue(n: Node) []const u8 {
        std.debug.assert(n.* == .attribute or n.* == .text or n.* == .cdata or n.* == .comment or n.* == .proc_inst);
        return switch (n) {
            .attribute => |a| std.mem.span(a.value),
            .text => |t| std.mem.span(t.value),
            .cdata => |t| std.mem.span(t.value),
            .comment => |t| std.mem.span(t.value),
            .proc_inst => |t| std.mem.span(t.value),
            else => unreachable
        };
    }

    // Render

    pub fn render(n: *Node, writer: anytype) !void {
        switch (n.*) {
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
  try testing.expectEqual(NodeType.cdata, comment.archetype());

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

  var text = try Node.Text(testing.allocator, "Hello", );
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

test "Element.attributes" {}
test "Element.append" {}
test "Element.prepend" {}
test "Element.children" {}

test "Attribute.getName" {
  var attr = try Node.Attr(testing.allocator, "title", "Mr");
  defer attr.deinit();
  try testing.expectEqualStrings("title", attr.getName());
}

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
