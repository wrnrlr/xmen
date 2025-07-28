const std = @import("std");
const dom = @import("./dom.zig");
const sax = @import("./sax.zig");

const Allocator = std.mem.Allocator;

const NodeType = dom.NodeType;
const Document = dom.Document;
const Element = dom.Element;
const Node = dom.Node;
const Text = dom.Text;
const Attr = dom.Attr;
const SaxParser = sax.SaxParser;
const Entity = sax.Entity;
const EntityType = sax.EntityType;

pub const DomParser = struct {
    allocator: std.mem.Allocator,
    document: *Node,
    current_element: ?*Node,
    element_stack: std.ArrayList(*Node),

    pub fn init(allocator: Allocator) !*DomParser {
        const parser = try allocator.create(DomParser);
        const doc_node = try allocator.create(Node);
        const doc = try allocator.create(Document);
        doc.* = Document.init(allocator);
        doc_node.* = Node{ .document = doc };

        parser.* = DomParser{
            .allocator = allocator,
            .document = doc_node,
            .current_element = null,
            .element_stack = std.ArrayList(*Node).init(allocator),
        };
        return parser;
    }

    pub fn deinit(self: *DomParser) void {
        // Free all nodes in the document
        for (self.document.document.children.items) |child| {
            freeNode(self.allocator, child);
        }
        self.document.deinit();
        self.allocator.destroy(self.document.document);
        self.allocator.destroy(self.document);
        self.element_stack.deinit();
        self.allocator.destroy(self);
    }

    fn freeNode(allocator: Allocator, node: *Node) void {
        std.debug.print("Attempting to free node of type: {}\n", .{node.getNodeType()});
        switch (node.*) {
            .element => |elem| {
                for (elem.attributes.items) |attr_node| {
                    switch (attr_node.*) {
                        .attribute => |attr| {
                            allocator.free(attr.name);
                            allocator.free(attr.value);
                            allocator.destroy(attr);
                        },
                        else => {},
                    }
                    allocator.destroy(attr_node);
                }
                for (elem.children.items) |child| {
                    freeNode(allocator, child);
                }
                allocator.free(elem.tagName);
                elem.deinit();
                allocator.destroy(elem);
            },
            .text => |text| {
                // Free content for all text-based node types
                if (text.nodeType == .text or text.nodeType == .cdata or
                    text.nodeType == .comment or text.nodeType == .processing_instruction) {
                    std.debug.print("Freeing text content of length: {}\n", .{text.content.len});
                    allocator.free(text.content);
                }
                allocator.destroy(text);
            },
            .attribute => |attr| {
                allocator.free(attr.name);
                allocator.free(attr.value);
                allocator.destroy(attr);
            },
            .document => {}, // Document is handled separately
        }
        allocator.destroy(node);
    }

    fn handleEvent(self: *DomParser, entity: Entity) !void {
        switch (entity.tag) {
            .open_tag => {
                const tag = entity.data.open_tag;
                const tag_name = tag.name[0..tag.name_len];
                const elem_node = try self.allocator.create(Node);
                const elem = try self.allocator.create(Element);
                elem.* = Element.init(self.allocator, try self.allocator.dupe(u8, tag_name));
                elem_node.* = Node{ .element = elem };

                if (self.current_element) |parent| {
                    _ = try parent.appendChild(elem_node);
                } else {
                    _ = try self.document.appendChild(elem_node);
                }

                // Handle attributes
                if (tag.attributes != null and tag.attributes_len > 0) {
                    const attrs = tag.attributes[0..tag.attributes_len];
                    for (attrs) |attr| {
                        const name = try self.allocator.dupe(u8, attr.name[0..attr.name_len]);
                        const value = try self.allocator.dupe(u8, attr.value[0..attr.value_len]);
                        const attr_node = try self.allocator.create(Node);
                        const attr_data = try self.allocator.create(Attr);
                        attr_data.* = Attr.init(name, value, elem_node);
                        attr_node.* = Node{ .attribute = attr_data };
                        try elem.setAttributeNode(elem_node, attr_node);
                    }
                }

                try self.element_stack.append(elem_node);
                self.current_element = elem_node;
            },
            .close_tag => {
                if (self.element_stack.items.len > 0) {
                    _ = self.element_stack.pop();
                }
                self.current_element = if (self.element_stack.items.len > 0)
                    self.element_stack.items[self.element_stack.items.len - 1]
                else
                    null;
            },
            .text => {
                const text_data = entity.data.text;
                const content = try self.allocator.dupe(u8, text_data.value[0..(text_data.header[1] - text_data.header[0])]);
                const text_node = try self.allocator.create(Node);
                const text = try self.allocator.create(Text);
                text.* = Text.text(content, self.current_element);
                text_node.* = Node{ .text = text };

                if (self.current_element) |parent| {
                    _ = try parent.appendChild(text_node);
                } else {
                    _ = try self.document.appendChild(text_node);
                }
            },
            .comment => {
                const comment_data = entity.data.comment;
                const content = try self.allocator.dupe(u8, comment_data.value[0..(comment_data.header[1] - comment_data.header[0])]);
                const text_node = try self.allocator.create(Node);
                const text = try self.allocator.create(Text);
                text.* = Text.comment(content, self.current_element);
                text_node.* = Node{ .text = text };

                if (self.current_element) |parent| {
                    _ = try parent.appendChild(text_node);
                } else {
                    _ = try self.document.appendChild(text_node);
                }
            },
            .processing_instruction => {
                const pi_data = entity.data.processing_instruction;
                const content = try self.allocator.dupe(u8, pi_data.value[0..(pi_data.header[1] - pi_data.header[0])]);
                const text_node = try self.allocator.create(Node);
                const text = try self.allocator.create(Text);
                text.* = Text.instruction(content, self.current_element);
                text_node.* = Node{ .text = text };

                if (self.current_element) |parent| {
                    _ = try parent.appendChild(text_node);
                } else {
                    _ = try self.document.appendChild(text_node);
                }
            },
            .cdata => {
                const cdata_data = entity.data.cdata;
                const content = try self.allocator.dupe(u8, cdata_data.value[0..(cdata_data.header[1] - cdata_data.header[0])]);
                const text_node = try self.allocator.create(Node);
                const text = try self.allocator.create(Text);
                text.* = Text.cdata(content, self.current_element);
                text_node.* = Node{ .text = text };

                if (self.current_element) |parent| {
                    _ = try parent.appendChild(text_node);
                } else {
                    _ = try self.document.appendChild(text_node);
                }
            },
        }
    }

    fn handleEventCallback(context: ?*anyopaque, entity: Entity) callconv(.C) void {
        const self: *DomParser = @ptrCast(@alignCast(context.?));
        self.handleEvent(entity) catch |err| {
            std.debug.print("Error handling event: {}\n", .{err});
        };
    }

    pub fn parse(self: *DomParser, xml: []const u8) !*Node {
        var parser = try SaxParser.init(self.allocator, self, &handleEventCallback);
        defer parser.deinit();
        try parser.write(xml);
        return self.document;
    }

    pub fn render(self: *DomParser, writer: anytype) !void {
        try self.document.render(writer);
    }
};

test "parse XML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<root id="1">
        \\    <child class="test">Hello, <b>World</b>!</child>
        \\    <![CDATA[<p>This is CDATA</p>]]>
        \\    <!-- This is a comment -->
        \\</root>
    ;

    var builder = try DomParser.init(allocator);
    defer builder.deinit();

    const doc = try builder.parse(xml);

    // Verify the document structure
    try std.testing.expectEqual(NodeType.document, doc.getNodeType());
    try std.testing.expect(doc.document.children.items.len > 0);

    // Verify first child is a processing instruction (XML declaration)
    const first_child = doc.document.children.items[0];
    std.debug.print("\nPI: {*} \n", .{first_child});
    // try std.testing.expectEqual(NodeType.processing_instruction, first_child.);
    try std.testing.expectEqualStrings("xml version=\"1.0\" encoding=\"UTF-8\"", first_child.text.content);

    // Verify second child is a text node (newline after XML declaration)
    const second_child = doc.document.children.items[1];
    try std.testing.expectEqual(NodeType.text, second_child.getNodeType());
    try std.testing.expectEqualStrings("\n", second_child.text.content);

    // Verify root element (third child)
    const root = doc.document.children.items[2];
    try std.testing.expectEqual(NodeType.element, root.getNodeType());
    try std.testing.expectEqualStrings("root", root.element.tagName);

    // Verify root attributes
    try std.testing.expectEqual(@as(usize, 1), root.element.attributes.items.len);
    try std.testing.expectEqualStrings("id", root.element.attributes.items[0].attribute.name);
    try std.testing.expectEqualStrings("1", root.element.attributes.items[0].attribute.value);

    // Verify child structure
    try std.testing.expectEqual(@as(usize, 7), root.element.children.items.len);

    // Verify child element
    const child = root.element.children.items[1];
    try std.testing.expectEqual(NodeType.element, child.getNodeType());
    try std.testing.expectEqualStrings("child", child.element.tagName);

    // Verify child attributes
    try std.testing.expectEqual(@as(usize, 1), child.element.attributes.items.len);
    try std.testing.expectEqualStrings("class", child.element.attributes.items[0].attribute.name);
    try std.testing.expectEqualStrings("test", child.element.attributes.items[0].attribute.value);

    // Verify nested text and bold element
    try std.testing.expectEqual(@as(usize, 3), child.element.children.items.len);
    try std.testing.expectEqual(NodeType.text, child.element.children.items[0].getNodeType());
    try std.testing.expectEqualStrings("Hello, ", child.element.children.items[0].text.content);

    // Verify CDATA
    const cdata = root.element.children.items[3];
    try std.testing.expectEqual(NodeType.cdata, cdata.getNodeType());
    try std.testing.expectEqualStrings("<p>This is CDATA</p>", cdata.text.content);

    // Verify comment
    const comment = root.element.children.items[5];
    try std.testing.expectEqual(NodeType.comment, comment.getNodeType());
    try std.testing.expectEqualStrings(" This is a comment ", comment.text.content);

    // Test rendering
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try builder.render(buffer.writer());
    try std.testing.expectEqualStrings(xml, buffer.items);
}
