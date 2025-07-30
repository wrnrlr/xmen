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
        name: [*]const u8,
        attributes: *NamedNodeMap = undefined,
        children: *NodeList = undefined,
        parent: ?*Node = null
    },
    attribute: struct {
        name: [*]const u8,
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
        children: *NodeList = undefined,
    },

    // Constructors

    pub fn Elem(alloc: Allocator, tag: []const u8) Node {
        return Node{ .element = .{ .alloc = alloc, .name = tag, .attributes = NamedNodeMap.init(alloc), .nodes = NodeList.init(alloc)} };
    }

    pub fn Attr(name: []const u8, value: []const u8) Node {
        return Node{ .attribute = .{ .name = name, .value = value } };
    }

    pub fn Text(content: []const u8) Node {
        return Node{ .text = .{ .content = content } };
    }

    pub fn CData(content: []const u8) Node {
      return Node{ .cdata = .{ .content = content } };
    }

    pub fn ProcInst(content: []const u8) Node {
      return Node{ .proc_inst = .{ .content = content } };
    }

    pub fn Comment(content: []const u8) Node {
      return Node{ .comment = .{ .content = content } };
    }

    pub fn Doc(alloc: Allocator) !Node {
      const kids = try alloc.create(NodeList);
      return Node{ .document = .{ .children = kids } };
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

    pub fn parent(n: *Node) ?*Node {
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

    fn free(n: Node, ptr: anytype) void {
      std.debug.assert(n == .element);
      switch(n) {
        .element => |e| e.alloc.destroy(ptr),
        else => {}
      }
    }

    pub fn deinit(n: Node) void {
      switch (n) {
        .element => |e| {
          // for (e.attributes.keys()) |key|
          //   e.alloc.destroy(key.ptr);
          // for (e.attributes.values()) |val|
          //   e.alloc.destroy(val);
          e.attributes.deinit();

          for (e.children.items) |child|
            child.deinit();
          e.children.deinit();
        },
        .attribute => |a| {
          if (a.parent==null) return;
          // a.parent.?.free(a.name.ptr);
          // a.parent.?.free(a.value.ptr);
        },
        .text => |_| {},
        .cdata => |_| {},
        .comment => |_| {},
        .proc_inst => |_| {},
        .document => |d| {
          d.children.deinit();
          // for (d.children.items) |child|
          //   child.deinit();
          // d.children.deinit();
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

    pub fn append(n: Node, child: *Node) void {
      std.debug.assert(n.* == .element or n.* == .document);
      std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .proc_inst);
      switch(n) {
        .element => |e| e.children.append(child),
        .document => |d| d.children.append(child),
        else => {}
      }
    }

    pub fn prepend(n: Node, child: Node) void {
      std.debug.assert(n.* == .element or n.* == .document);
      std.debug.assert(child.* == .element or child.* == .text or child.* == .cdata or child.* == .comment or child.* == .processing_instruction);
      switch(n) {
        .element => |e| e.children.prepend(child),
        .document => |d| d.children.prepend(child),
        else => {}
      }
    }

    // Named nodes: Elem & Attr

    pub fn getName(n: Node) [*]const u8 {
      std.debug.assert(n.* == .element or n.* == .attribute);
      return switch (n) {
        .element => |a| a.name,
        .attribute => |a| a.name,
        else => {}
      };
    }

    // Elem

    pub fn attributes(n: Node) *NamedNodeMap {
      std.debug.assert(n.* == .element);
      return switch(n) {
        .element => |e| e.attributes,
        else => {}
      };
    }

    // Value Nodes:  Attr, Text, CData, Comment, ProcInst

    pub fn setValue(n: Node, value: [*]const u8) void {
        std.debug.assert(n.* == .attribute or n.* == .text or n.* == .cdata or n.* == .comment or n.* == .proc_inst);
        switch (n) {
            .attribute => |a| a.value = value,
            else => {}
        }
    }

    pub fn getValue(n: Node) [*]const u8 {
        std.debug.assert(n.* == .attribute or n.* == .text or n.* == .cdata or n.* == .comment or n.* == .proc_inst);
        return switch (n) {
            .attribute => |a| a.value,
            .text => |t| t.value,
            .cdata => |t| t.value,
            .comment => |t| t.value,
            .proc_inst => |t| t.value,
            else => {}
        };
    }

    // Render

    pub fn render(n: Node, writer: anytype) void {
      switch (n) {
          .element => |e| {
              try writer.print("<{s}", .{e.tagName});
              for (e.attributes.items, 0..) |attr, i| {
                  if (i!=0) writer.print(" ");
                  try attr.render(writer);
              }
              try writer.print(">", .{});
              for (e.children.items) |child| try child.render(writer);
              try writer.print("</{s}>", .{e.tagName});
          },
          .attribute => |a| writer.print("{s}=\"{s}\"", .{ a.name, a.value }),
          .text => |t| writer.print("{s}", .{ t.content }),
          .cdata => |t| writer.print("<![CDATA[{s}]]>", .{ t.content }),
          .proc_inst => |t| writer.print("<?{s}?>", .{ t.content }),
          .comment => |t| writer.print("<!--{s}-->", .{ t.content }),
          .document => |d| for (d.children.items) |child| try child.render(writer)
      }
    }
};

const testing = std.testing;

test "Elem" {}
test "Element.archetype" {}
test "Element.parent" {}
test "Element.getName" {}
test "Element.attributes" {}
test "Element.children" {}

test "Attribute" {}
test "Attribute.archetype" {}
test "Attribute.parent" {}
test "Attribute.getName" {}
test "Attribute.getValue" {}
test "Attribute.setValue" {}

test "Text" {}
test "Text.archetype" {}
test "Text.parent" {}
test "Text.getValue" {}
test "Text.setValue" {}

test "CData" {}
test "CData.archetype" {}
test "CData.parent" {}

test "Comment" {}
test "Comment.archetype" {}
test "Comment.parent" {}

test "ProcInst" {}
test "ProcInst.archetype" {}
test "ProcInst.parent" {}

test "Doc" {
  const doc = try Node.Doc(testing.allocator);
  defer doc.deinit();
  try testing.expectEqual(NodeType.document, doc.archetype());
}
