const std = @import("std");
const dom = @import("dom.zig");
const sax = @import("sax.zig");

const Allocator = std.mem.Allocator;

const Node = dom.Node;

pub const DomParser = struct {
    allocator: Allocator,
    document: *Node,
    current_element: ?*Node,
    element_stack: std.ArrayList(*Node),

    pub fn init(allocator: Allocator) !*DomParser {
        const parser = try allocator.create(DomParser);
        const doc = try Node.Doc(allocator);
        parser.* = .{
            .allocator = allocator,
            .document = doc,
            .current_element = null,
            .element_stack = std.ArrayList(*Node).init(allocator),
        };
        return parser;
    }

    pub fn deinit(self: *DomParser) void {
        self.document.destroy();
        self.element_stack.deinit();
        self.allocator.destroy(self);
    }

    fn handleEvent(self: *DomParser, entity: sax.Entity) !void {
        switch (entity.tag) {
            .open_tag => {
                const tag = entity.data.open_tag;
                const tag_name = tag.name[0..tag.name_len];
                const elem = try Node.Elem(self.allocator, tag_name);

                if (self.current_element) |parent| {
                    try parent.append(elem);
                } else {
                    try self.document.append(elem);
                }

                // Handle attributes
                if (tag.attributes != null and tag.attributes_len > 0) {
                    const attrs = tag.attributes[0..tag.attributes_len];
                    for (attrs) |attr| {
                        const attr_name = attr.name[0..attr.name_len];
                        const attr_value = attr.value[0..attr.value_len];
                        try elem.setAttribute(attr_name, attr_value);
                    }
                }

                try self.element_stack.append(elem);
                self.current_element = elem;
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
                const content = text_data.value[0..(text_data.header[1] - text_data.header[0])];
                const text_node = try Node.Text(self.allocator, content);

                if (self.current_element) |parent| {
                    try parent.append(text_node);
                } else {
                    try self.document.append(text_node);
                }
            },
            .comment => {
                const comment_data = entity.data.comment;
                const content = comment_data.value[0..(comment_data.header[1] - comment_data.header[0])];
                const comment_node = try Node.Comment(self.allocator, content);

                if (self.current_element) |parent| {
                    try parent.append(comment_node);
                } else {
                    try self.document.append(comment_node);
                }
            },
            .processing_instruction => {
                const pi_data = entity.data.processing_instruction;
                const content = pi_data.value[0..(pi_data.header[1] - pi_data.header[0])];
                const pi_node = try Node.ProcInst(self.allocator, content);

                if (self.current_element) |parent| {
                    try parent.append(pi_node);
                } else {
                    try self.document.append(pi_node);
                }
            },
            .cdata => {
                const cdata_data = entity.data.cdata;
                const content = cdata_data.value[0..(cdata_data.header[1] - cdata_data.header[0])];
                const cdata_node = try Node.CData(self.allocator, content);

                if (self.current_element) |parent| {
                    try parent.append(cdata_node);
                } else {
                    try self.document.append(cdata_node);
                }
            },
        }
    }

    fn handleEventCallback(context: ?*anyopaque, entity: sax.Entity) callconv(.C) void {
        const self: *DomParser = @ptrCast(@alignCast(context.?));
        self.handleEvent(entity) catch |err| {
            std.debug.print("Error handling event: {}\n", .{err});
        };
    }

    pub fn parse(self: *DomParser, xml: []const u8) !*Node {
        var parser = try sax.SaxParser.init(self.allocator, self, &handleEventCallback);
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
    try std.testing.expectEqual(dom.NodeType.document, doc.archetype());

    // Verify first child is a processing instruction (XML declaration)
    const first_child = doc.document.children.item(0).?;
    try std.testing.expectEqual(dom.NodeType.proc_inst, first_child.archetype());
    try std.testing.expectEqualStrings("xml version=\"1.0\" encoding=\"UTF-8\"", first_child.getContent());

    // Verify second child is a text node (newline after XML declaration)
    const second_child = doc.document.children.item(1).?;
    try std.testing.expectEqual(dom.NodeType.text, second_child.archetype());
    try std.testing.expectEqualStrings("\n", second_child.getContent());

    // Verify root element (third child)
    const root = doc.document.children.item(2).?;
    try std.testing.expectEqual(dom.NodeType.element, root.archetype());
    try std.testing.expectEqualStrings("root", root.tagName());

    // Verify root attributes
    try std.testing.expectEqual(@as(usize, 1), root.attributes().length());
    try std.testing.expectEqualStrings("1", root.getAttribute("id").?);

    // Verify child structure
    try std.testing.expectEqual(@as(usize, 7), root.children().length());

    // Verify child element
    const child = root.children().item(1).?;
    try std.testing.expectEqual(dom.NodeType.element, child.archetype());
    try std.testing.expectEqualStrings("child", child.tagName());

    // Verify child attributes
    try std.testing.expectEqual(@as(usize, 1), child.attributes().length());
    try std.testing.expectEqualStrings("test", child.getAttribute("class").?);

    // Verify nested text and bold element
    try std.testing.expectEqual(@as(usize, 3), child.children().length());
    try std.testing.expectEqual(dom.NodeType.text, child.children().item(0).?.archetype());
    try std.testing.expectEqualStrings("Hello, ", child.children().item(0).?.getContent());

    // Verify CDATA
    const cdata = root.children().item(3).?;
    try std.testing.expectEqual(dom.NodeType.cdata, cdata.archetype());
    try std.testing.expectEqualStrings("<p>This is CDATA</p>", cdata.getContent());

    // Verify comment
    const comment = root.children().item(5).?;
    try std.testing.expectEqual(dom.NodeType.comment, comment.archetype());
    try std.testing.expectEqualStrings(" This is a comment ", comment.getContent());

    // Test rendering
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try builder.render(buffer.writer());
    try std.testing.expectEqualStrings(xml, buffer.items);
}
