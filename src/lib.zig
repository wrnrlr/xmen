const std = @import("std");
const dom = @import("./dom.zig");
const sax = @import("./sax.zig");
const xpath = @import("./xpath.zig");
const eval = @import("./eval.zig");

const Allocator = std.mem.Allocator;

pub const Document = dom.Document;
pub const Element = dom.Element;
pub const Node = dom.Node;
pub const Text = dom.Text;
pub const Attr = dom.Attr;

pub const SaxParser = sax.SaxParser;
pub const SaxEvent = sax.SaxEvent;

pub const XPathParser = xpath.XPathParser;

pub const XPathEvaluator = eval.XPathEvaluator;
pub const XPathResult = eval.XPathResult;
pub const XPathError = eval.XPathError;

pub const DomParser = struct {
    allocator: Allocator,
    document: *Document,
    current_element: ?*Element,
    element_stack: std.ArrayList(*Element),

    pub fn init(allocator: Allocator) !*DomParser {
        const builder = try allocator.create(DomParser);
        const document = try allocator.create(Document);
        document.* = Document{
            .nodeType = .document_node,
            .tagName = "#document",
            .children = std.ArrayList(Node).init(allocator),
        };
        builder.* = DomParser{
            .allocator = allocator,
            .document = document,
            .current_element = null,
            .element_stack = std.ArrayList(*Element).init(allocator),
        };
        return builder;
    }

    pub fn deinit(self: *DomParser) void {
        for (self.document.children.items) |*node| {
            switch (node.*) {
                .element => |elem| {
                    for (elem.attributes.items) |attr| {
                        self.allocator.free(attr.name);
                        self.allocator.free(attr.value);
                    }
                    elem.attributes.deinit();
                    for (elem.children.items) |*child| {
                        self.freeNode(child);
                    }
                    elem.children.deinit();
                    self.allocator.free(elem.tagName);
                    self.allocator.destroy(elem);
                },
                .text => |text| {
                    self.allocator.free(text.content);
                    self.allocator.destroy(text);
                },
                .attribute => |attr| {
                    self.allocator.free(attr.name);
                    self.allocator.free(attr.value);
                    self.allocator.destroy(attr);
                },
                .document => unreachable,
            }
        }
        self.document.children.deinit();
        self.allocator.destroy(self.document);
        self.element_stack.deinit();
        self.allocator.destroy(self);
    }

    pub fn freeNode(self: *DomParser, node: *Node) void {
        switch (node.*) {
            .element => |elem| {
                for (elem.attributes.items) |attr| {
                    self.allocator.free(attr.name);
                    self.allocator.free(attr.value);
                }
                elem.attributes.deinit();
                for (elem.children.items) |*child| {
                    self.freeNode(child);
                }
                elem.children.deinit();
                self.allocator.free(elem.tagName);
                self.allocator.destroy(elem);
            },
            .text => |text| {
                self.allocator.free(text.content);
                self.allocator.destroy(text);
            },
            .attribute => |attr| {
                self.allocator.free(attr.name);
                self.allocator.free(attr.value);
                self.allocator.destroy(attr);
            },
            .document => unreachable,
        }
    }

    fn handleEvent(self: *DomParser, event: SaxEvent) !void {
        switch (event.type) {
            .Open => {
                const elem = try self.allocator.create(Element);
                const tag_name = try self.allocator.dupe(u8, event.name.ptr[0..event.name.len]);
                elem.* = Element{
                    .nodeType = .element_node,
                    .tagName = tag_name,
                    .attributes = std.ArrayList(Attr).init(self.allocator),
                    .children = std.ArrayList(Node).init(self.allocator),
                    .parentElement = self.current_element,
                };

                if (event.attributes.len > 0) {
                    const attrs = event.attributes.ptr.?[0..event.attributes.len];
                    for (attrs) |attr| {
                        const name = try self.allocator.dupe(u8, attr.name.ptr[0..attr.name.len]);
                        const value = try self.allocator.dupe(u8, attr.value.ptr[0..attr.value.len]);
                        try elem.attributes.append(Attr{
                            .nodeType = .attribute_node,
                            .name = name,
                            .value = value,
                            .parentElement = elem,
                        });
                    }
                }

                var node = Node{ .element = elem };
                if (self.current_element) |parent| {
                    _ = try parent.appendChild(&node);
                } else {
                    try self.document.children.append(node);
                }

                try self.element_stack.append(elem);
                self.current_element = elem;
            },
            .Close => {
                if (self.element_stack.items.len > 0) {
                    _ = self.element_stack.pop();
                }
                self.current_element = if (self.element_stack.items.len > 0)
                    self.element_stack.items[self.element_stack.items.len - 1]
                else null;
            },
            .Text => {
                if (event.name.len > 0) {
                    const text = try self.allocator.create(Text);
                    const text_content = try self.allocator.dupe(u8, event.name.ptr[0..event.name.len]);
                    text.* = Text{
                        .nodeType = .text_node,
                        .content = text_content,
                        .parentElement = self.current_element,
                    };
                    var node = Node{ .text = text };
                    if (self.current_element) |parent| {
                        _ = try parent.appendChild(&node);
                    } else {
                        try self.document.children.append(node);
                    }
                }
            },
            .Comment => {
                // Optionally handle comments if needed
            },
            .ProcessingInstruction => {
                // Optionally handle processing instructions if needed
            },
            .Cdata => {
                const text = try self.allocator.create(Text);
                const cdata_content = try self.allocator.dupe(u8, event.name.ptr[0..event.name.len]);
                text.* = Text{
                    .nodeType = .cdata_section_node,
                    .content = cdata_content,
                    .parentElement = self.current_element,
                };
                var node = Node{ .text = text };
                if (self.current_element) |parent| {
                    _ = try parent.appendChild(&node);
                } else {
                    try self.document.children.append(node);
                }
            },
        }
    }

    fn handleEventCallback(context: ?*anyopaque, event: SaxEvent) callconv(.C) void {
        const self: *DomParser = @ptrCast(@alignCast(context.?));
        self.handleEvent(event) catch |err| {
            std.debug.print("Error handling event: {}\n", .{err});
        };
    }

    pub fn parse(self: *DomParser, xml: []const u8) !*Document {
        var parser = try SaxParser.init(self.allocator, self, &handleEventCallback);
        defer parser.deinit();
        parser.write(xml);
        return self.document;
    }

    fn render(self: *DomParser, writer: anytype) !void {
        for (self.document.children.items) |child| {
            try child.render(writer);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    _ = try builder.parse(xml);

    const stdout = std.io.getStdOut().writer();
    try builder.render(stdout);
}
