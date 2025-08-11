// SAX parser for XML
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Position = extern struct {
    line: u64,
    char: u64,
};

pub const Text = extern struct {
    value: [*c]const u8,
    start: Position,
    end: Position,
    header: [2]usize,

    pub inline fn content(self:Text) []const u8 {
      return self.value[0..(self.header[1] - self.header[0])];
    }
};

pub const Attr = extern struct {
    name: [*c]const u8,
    name_len: usize,
    value: [*c]const u8,
    value_len: usize,
};

pub const Tag = extern struct {
    name: [*c]const u8,
    name_len: usize,
    attributes: [*c]Attr,
    attributes_len: usize,
    start: Position,
    end: Position,
    header: [2]usize,
};

pub const EntityType = enum(c_int) {
    open_tag,
    close_tag,
    text,
    comment,
    processing_instruction,
    cdata,
};

pub const Entity = extern struct {
    tag: EntityType,
    data: extern union {
        open_tag: Tag,
        close_tag: Tag,
        text: Text,
        comment: Text,
        processing_instruction: Text,
        cdata: Text,
    },
};

const State = enum {
    Text,
    IgnoreComment,
    IgnoreInstruction,
    TagName,
    Tag,
    AttrName,
    AttrEq,
    AttrQuot,
    AttrValue,
    Cdata,
    IgnoreCdata,
};

pub const ParseError = error{
    UnexpectedEndOfInput,
    InvalidCharacter,
    UnterminatedString,
    MalformedEntity,
    AttributeLimitExceeded
};

pub const SaxParser = struct {
    allocator: Allocator,
    buffer: []const u8,
    pos: usize,
    state: State,
    tag_name: []const u8,
    end_tag: bool,
    self_closing: bool,
    attr_name: []const u8,
    attr_value: []const u8,
    attributes: std.ArrayList(Attr),
    context: ?*anyopaque,
    on_event: ?*const fn (?*anyopaque, Entity) callconv(.C) void,
    tag_start_byte: usize,

    pub fn init(allocator: Allocator, context: ?*anyopaque, callback: ?*const fn (?*anyopaque, Entity) callconv(.C) void) !SaxParser {
        return SaxParser{
            .allocator = allocator,
            .buffer = &.{},
            .pos = 0,
            .state = .Text,
            .tag_name = "",
            .end_tag = false,
            .self_closing = false,
            .attr_name = "",
            .attr_value = "",
            .attributes = std.ArrayList(Attr).init(allocator),
            .context = context,
            .on_event = callback,
            .tag_start_byte = 0,
        };
    }

    pub fn deinit(self: *SaxParser) void {
        self.attributes.deinit();
    }

    // Simplified write function using helpers
    pub fn write(self: *SaxParser, input: []const u8) ParseError!void {
        self.buffer = input;
        self.pos = 0;
        var record_start: usize = 0;
        var quote_char: ?u8 = null;

        while (self.pos < self.buffer.len) : (self.pos += 1) {
            const c = self.buffer[self.pos];

            switch (self.state) {
                .Text => {
                    if (c == '<') {
                        // Emit any accumulated text
                        if (self.pos > record_start) {
                            try self.emitText(record_start, self.pos, .text);
                        }

                        self.tag_start_byte = self.pos;
                        self.state = self.detectSpecialConstruct();
                        self.end_tag = false;
                        self.self_closing = false;
                        record_start = self.pos + 1;
                    }
                },
                .IgnoreComment => {
                    if (try self.tryCompleteComment(record_start)) {
                        record_start = self.pos + 1;
                    }
                },
                .IgnoreInstruction => {
                    if (try self.tryCompleteProcessingInstruction(record_start)) {
                        record_start = self.pos + 1;
                    }
                },
                .Cdata => {
                    if (try self.tryCompleteCdata(record_start)) {
                        record_start = self.pos + 1;
                    }
                },
                .TagName => {
                    if (isWhitespace(c)) {
                        self.tag_name = self.buffer[record_start..self.pos];
                        self.state = .Tag;
                        record_start = self.pos + 1;
                    } else if (c == '/') {
                        if (try self.handleSelfClosingTag()) {
                            record_start = self.pos + 1;
                        }
                    } else if (c == '>') {
                        self.tag_name = self.buffer[record_start..self.pos];
                        try self.completeTag();
                        record_start = self.pos + 1;
                    }
                },
                .Tag => {
                    if (c == '>') {
                        try self.completeTag();
                        record_start = self.pos + 1;
                    } else if (!isWhitespace(c)) {
                        self.state = .AttrName;
                        record_start = self.pos;
                    }
                },
                .AttrName => {
                    if (c == '=') {
                        self.attr_name = self.buffer[record_start..self.pos];
                        self.state = .AttrEq;
                        record_start = self.pos + 1;
                    } else if (isWhitespace(c) or c == '>') {
                        self.attr_name = self.buffer[record_start..self.pos];
                        try self.addAttribute(self.attr_name, "");
                        self.state = .Tag;
                        record_start = self.pos + 1;
                        if (c == '>') {
                            self.pos -= 1; // Reprocess '>' in Tag state
                        }
                    } else if (c == '/') {
                        if (try self.handleSelfClosingTag()) {
                            record_start = self.pos + 1;
                        }
                    }
                },
                .AttrEq => {
                    if (c == '"' or c == '\'') {
                        quote_char = c;
                        self.state = .AttrQuot;
                        record_start = self.pos + 1;
                    } else if (!isWhitespace(c)) {
                        // Unquoted attribute value (non-standard but sometimes seen)
                        self.state = .AttrValue;
                        record_start = self.pos;
                    }
                },
                .AttrQuot => {
                    if (c == quote_char) {
                        self.attr_value = self.buffer[record_start..self.pos];
                        try self.addAttribute(self.attr_name, self.attr_value);
                        self.state = .Tag;
                        record_start = self.pos + 1;
                        quote_char = null;
                    }
                },
                .AttrValue => {
                    if (isWhitespace(c) or c == '>' or c == '/') {
                        self.attr_value = self.buffer[record_start..self.pos];
                        try self.addAttribute(self.attr_name, self.attr_value);
                        self.state = .Tag;
                        record_start = self.pos + 1;
                        if (c == '>' or c == '/') {
                            self.pos -= 1; // Reprocess in Tag state
                        }
                    }
                },
                .IgnoreCdata => {
                    // This state is not used in the current implementation
                    // but could be used for ignoring CDATA sections
                },
            }
        }
    }

    fn get_position(self: *SaxParser, byte_pos: usize) Position {
        var line: u64 = 1;
        var char: u64 = 1;
        var pos: usize = 0;
        while (pos < byte_pos and pos < self.buffer.len) {
            const byte = self.buffer[pos];
            if (byte < 0x80 or byte >= 0xC0) {
                if (byte == '\n') {
                    line += 1;
                    char = 1;
                } else {
                    char += 1;
                }
            }
            pos += 1;
        }
        return Position{ .line = line, .char = char };
    }

    fn emitOpenTag(self: *SaxParser) ParseError!void {
        const tag_header = [_]usize{ self.tag_start_byte, self.pos + 1 };
        const open_tag = Tag{
            .name = self.tag_name.ptr,
            .name_len = self.tag_name.len,
            .attributes = if (self.attributes.items.len > 0) self.attributes.items.ptr else null,
            .attributes_len = self.attributes.items.len,
            .start = self.get_position(self.tag_start_byte),
            .end = self.get_position(self.pos),
            .header = tag_header,
        };

        const entity = Entity{ .tag = .open_tag, .data = .{ .open_tag = open_tag } };
        if (self.on_event) |callback| {
            callback(self.context, entity);
        }

        self.attributes.clearRetainingCapacity();
    }

    // Helper function to emit close tag events
    fn emitCloseTag(self: *SaxParser) ParseError!void {
        const tag_header = [_]usize{ self.tag_start_byte, self.pos + 1 };
        const close_tag = Tag{
            .name = self.tag_name.ptr,
            .name_len = self.tag_name.len,
            .attributes = null,
            .attributes_len = 0,
            .start = self.get_position(self.tag_start_byte),
            .end = self.get_position(self.pos),
            .header = tag_header,
        };

        const entity = Entity{ .tag = .close_tag, .data = .{ .close_tag = close_tag } };
        if (self.on_event) |callback| {
            callback(self.context, entity);
        }
    }

    // Helper function to emit text events
    fn emitText(self: *SaxParser, start_pos: usize, end_pos: usize, entity_type: EntityType) ParseError!void {
        if (end_pos <= start_pos) return; // No content to emit

        const text_header = [_]usize{ start_pos, end_pos };
        const text_value = self.buffer[text_header[0]..text_header[1]];
        const text_entity = Text{
            .value = text_value.ptr,
            .header = text_header,
            .start = self.get_position(text_header[0]),
            .end = self.get_position(end_pos - 1),
        };

        const entity = Entity{
            .tag = entity_type,
            .data = switch (entity_type) {
                .text => .{ .text = text_entity },
                .comment => .{ .comment = text_entity },
                .cdata => .{ .cdata = text_entity },
                .processing_instruction => .{ .processing_instruction = text_entity },
                else => return ParseError.InvalidCharacter,
            }
        };

        if (self.on_event) |callback| {
            callback(self.context, entity);
        }
    }

    // Helper function to handle tag completion (both open and close)
    fn completeTag(self: *SaxParser) ParseError!void {
        if (self.end_tag) {
            try self.emitCloseTag();
        } else {
            try self.emitOpenTag();
        }

        self.state = .Text;
        return;
    }

    // Helper function to add an attribute safely
    fn addAttribute(self: *SaxParser, name: []const u8, value: []const u8) ParseError!void {
        if (name.len == 0 or std.mem.eql(u8, name, "/")) {
            return;
        }

        self.attributes.append(.{
            .name = name.ptr,
            .name_len = name.len,
            .value = value.ptr,
            .value_len = value.len,
        }) catch |err| switch (err) {
            error.OutOfMemory => return ParseError.AttributeLimitExceeded,
        };
    }

    // Helper function to handle comment end detection
    fn tryCompleteComment(self: *SaxParser, record_start: usize) ParseError!bool {
        if (self.pos + 2 >= self.buffer.len) return false;

        if (std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "-->")) {
            try self.emitText(record_start, self.pos, .comment);
            self.pos += 2; // Skip the remaining "-->"
            self.state = .Text;
            return true;
        }
        return false;
    }

    // Helper function to handle processing instruction end
    fn tryCompleteProcessingInstruction(self: *SaxParser, record_start: usize) ParseError!bool {
        if (self.pos + 1 >= self.buffer.len) return false;

        if (std.mem.eql(u8, self.buffer[self.pos .. self.pos + 2], "?>")) {
            try self.emitText(record_start, self.pos, .processing_instruction);
            self.pos += 1; // Skip the remaining "?>"
            self.state = .Text;
            return true;
        }
        return false;
    }

    // Helper function to handle CDATA end detection
    fn tryCompleteCdata(self: *SaxParser, record_start: usize) ParseError!bool {
        if (self.pos + 2 >= self.buffer.len) return false;

        if (std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "]]>")) {
            try self.emitText(record_start, self.pos, .cdata);
            self.pos += 2; // Skip the remaining "]]>"
            self.state = .Text;
            return true;
        }
        return false;
    }

    // Helper function to check if character is whitespace
    inline fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    // Helper function to handle self-closing tag detection
    fn handleSelfClosingTag(self: *SaxParser) ParseError!bool {
        if (self.pos + 1 >= self.buffer.len) return false;

        if (self.buffer[self.pos + 1] == '>') {
            self.self_closing = true;
            self.pos += 1; // Skip the '>'
            try self.emitOpenTag();
            self.state = .Text;
            return true;
        }
        return false;
    }

    // Helper function to detect and handle special XML constructs
    fn detectSpecialConstruct(self: *SaxParser) State {
        // Check for comments
        if (self.pos + 3 < self.buffer.len and
            std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 4], "!--")) {
            self.pos += 3; // Skip "!--"
            return .IgnoreComment;
        }

        // Check for CDATA
        if (self.pos + 8 < self.buffer.len and
            std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 9], "![CDATA[")) {
            self.pos += 8; // Skip "![CDATA["
            return .Cdata;
        }

        // Check for processing instructions
        if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '?') {
            self.pos += 1; // Skip "?"
            return .IgnoreInstruction;
        }

        // Check for closing tag
        if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '/') {
            self.end_tag = true;
            self.pos += 1; // Skip "/"
            return .TagName;
        }

        // Regular opening tag
        return .TagName;
    }
};

pub export fn create_parser(allocator: *Allocator, context: ?*anyopaque, callback: ?*const fn (?*anyopaque, Entity) callconv(.C) void) ?*SaxParser {
    const parser = allocator.create(SaxParser) catch return null;
    parser.* = SaxParser.init(allocator.*, context, callback) catch return null;
    return parser;
}

pub export fn destroy_parser(parser: *SaxParser) void {
    parser.deinit();
    parser.allocator.destroy(parser);
}

// pub export fn parse(parser: *SaxParser, input: [*]const u8, len: usize) void {
//     _ = parser.write(input[0..len]) catch |err| {
//         std.debug.print("Error in parser.write: {any}\n", .{err});
//         return;
//     };
// }

const testing = std.testing;

pub fn handlerCallback(context: ?*anyopaque, entity: Entity) callconv(.C) void {
    const handler: *TestEventHandler = @ptrCast(@alignCast(context));
    handler.handle(entity);
}

fn setupParser(allocator: Allocator, handler: *TestEventHandler) !SaxParser {
    return SaxParser.init(allocator, handler, handlerCallback);
}

pub const TestEventHandler = struct {
    allocator: Allocator,
    attributes: std.ArrayList(Attr),
    texts: std.ArrayList(Text),
    tags: std.ArrayList(Tag),
    proc_insts: std.ArrayList(Text),

    pub fn init(allocator: Allocator) TestEventHandler {
        return .{
            .allocator = allocator,
            .attributes = std.ArrayList(Attr).init(allocator),
            .texts = std.ArrayList(Text).init(allocator),
            .tags = std.ArrayList(Tag).init(allocator),
            .proc_insts = std.ArrayList(Text).init(allocator),
        };
    }

    pub fn deinit(self: *TestEventHandler) void {
        self.attributes.deinit();
        self.texts.deinit();
        self.tags.deinit();
        self.proc_insts.deinit();
    }

    pub fn handle(self: *TestEventHandler, entity: Entity) void {
        switch (entity.tag) {
            .open_tag => {
                self.tags.append(entity.data.open_tag) catch {};
                if (entity.data.open_tag.attributes != null and entity.data.open_tag.attributes_len > 0) {
                    const attrs_slice = entity.data.open_tag.attributes[0..entity.data.open_tag.attributes_len];
                    for (attrs_slice) |attr| {
                        self.attributes.append(attr) catch {};
                    }
                }
            },
            .close_tag => self.tags.append(entity.data.close_tag) catch {}, // Fixed to use .close_tag
            .text => self.texts.append(entity.data.text) catch {},
            .comment => self.texts.append(entity.data.comment) catch {},
            .processing_instruction => self.proc_insts.append(entity.data.processing_instruction) catch {},
            .cdata => self.texts.append(entity.data.cdata) catch {},
        }
    }
};

test "test_attribute" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<body class=\"\"></body> <component data-id=\"user_1234\" key=\"23\" disabled />";
    try parser.write(input);

    const attrs = handler.attributes.items;
    const texts = handler.texts.items;

    try testing.expectEqual(4, attrs.len);
    try testing.expectEqualStrings("", attrs[0].value[0..attrs[0].value_len]);
    try testing.expectEqual(1, texts.len);
    try testing.expectEqualStrings(" ", texts[0].value[0..(texts[0].header[1] - texts[0].header[0])]);
}

test "test_comments" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><!--Comment without whitespace--><element>content</element><!-- Comment with whitespace --></root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(3, texts.len); // 2 comments + 1 text content

    const first_comment = texts[0].value[0..(texts[0].header[1] - texts[0].header[0])];
    try testing.expectEqualStrings("Comment without whitespace", first_comment);

    const text_content = texts[1].value[0..(texts[1].header[1] - texts[1].header[0])];
    try testing.expectEqualStrings("content", text_content);

    const second_comment = texts[2].value[0..(texts[2].header[1] - texts[2].header[0])];
    try testing.expectEqualStrings(" Comment with whitespace ", second_comment);
}

test "test_comment_with_whitespace" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><!-- This is a comment --></root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(1, texts.len); // 1 comment

    const comment_content = texts[0].value[0..(texts[0].header[1] - texts[0].header[0])];
    try testing.expectEqualStrings(" This is a comment ", comment_content);
}

// Other test cases remain unchanged...
test "test_nested_elements" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><parent><child>content</child></parent></root>";
    try parser.write(input);

    const tags = handler.tags.items;
    try testing.expectEqual(6, tags.len); // 3 open, 3 close

    try testing.expectEqualStrings("root", tags[0].name[0..tags[0].name_len]);
    try testing.expectEqualStrings("parent", tags[1].name[0..tags[1].name_len]);
    try testing.expectEqualStrings("child", tags[2].name[0..tags[2].name_len]);
}

test "test_multiple_attributes" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<element id=\"test\" class=\"main\" data-value=\"123\" enabled=\"true\"></element>";
    try parser.write(input);

    const attrs = handler.attributes.items;
    try testing.expectEqual(4, attrs.len);

    try testing.expectEqualStrings("id", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("test", attrs[0].value[0..attrs[0].value_len]);

    try testing.expectEqualStrings("class", attrs[1].name[0..attrs[1].name_len]);
    try testing.expectEqualStrings("main", attrs[1].value[0..attrs[1].value_len]);

    try testing.expectEqualStrings("data-value", attrs[2].name[0..attrs[2].name_len]);
    try testing.expectEqualStrings("123", attrs[2].value[0..attrs[2].value_len]);
}

test "test_mixed_quotes_in_attributes" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<element title='He said \"Hello\"' description=\"It's working\"></element>";
    try parser.write(input);

    const attrs = handler.attributes.items;
    try testing.expectEqual(2, attrs.len);

    try testing.expectEqualStrings("title", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("He said \"Hello\"", attrs[0].value[0..attrs[0].value_len]);

    try testing.expectEqualStrings("description", attrs[1].name[0..attrs[1].name_len]);
    try testing.expectEqualStrings("It's working", attrs[1].value[0..attrs[1].value_len]);
}

test "test_empty_elements" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><empty></empty><another/></root>";
    try parser.write(input);

    const tags = handler.tags.items;
    try testing.expectEqual(5, tags.len); // root open, empty open, empty close, another open+close, root close
}

test "test_whitespace_handling" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input =
        \\<root>
        \\  <element   attr1="value1"   attr2="value2"  >
        \\    Content with spaces
        \\  </element>
        \\</root>
    ;
    try parser.write(input);

    _ = handler.texts.items;
    const attrs = handler.attributes.items;

    try testing.expectEqual(2, attrs.len);
    try testing.expectEqualStrings("attr1", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("value1", attrs[0].value[0..attrs[0].value_len]);
}

test "test_cdata_sections" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><![CDATA[This is <raw> content & data]]></root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(1, texts.len);

    const cdata_content = texts[0].value[0..(texts[0].header[1] - texts[0].header[0])];
    try testing.expectEqualStrings("This is <raw> content & data", cdata_content);
}

test "test_multiple_cdata_sections" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><![CDATA[First section]]><![CDATA[Second section]]></root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(2, texts.len);
}

test "test_processing_instructions" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root><?custom-instruction data?></root>";
    try parser.write(input);

    const proc_insts = handler.proc_insts.items;
    try testing.expectEqual(2, proc_insts.len);

    const first_pi = proc_insts[0].value[0..(proc_insts[0].header[1] - proc_insts[0].header[0])];
    try testing.expectEqualStrings("xml version=\"1.0\" encoding=\"UTF-8\"", first_pi);
}

test "test_complex_nested_structure" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input =
        \\<?xml version="1.0"?>
        \\<document xmlns="http://example.com">
        \\  <!-- Document header -->
        \\  <header id="main-header" class="primary">
        \\    <title>Test Document</title>
        \\    <metadata>
        \\      <author>Test Author</author>
        \\      <created>2024-01-01</created>
        \\    </metadata>
        \\  </header>
        \\  <body>
        \\    <section id="intro">
        \\      <p>Introduction paragraph with <em>emphasis</em>.</p>
        \\      <![CDATA[Raw content here & special chars < >]]>
        \\    </section>
        \\  </body>
        \\</document>
    ;
    try parser.write(input);

    const tags = handler.tags.items;
    const attrs = handler.attributes.items;
    _ = handler.texts.items;
    const proc_insts = handler.proc_insts.items;

    try testing.expect(tags.len > 10);
    try testing.expect(attrs.len >= 3);
    try testing.expect(proc_insts.len == 1);
}

test "test_edge_case_empty_attributes" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<element empty=\"\" another=\"value\" also-empty=''></element>";
    try parser.write(input);

    const attrs = handler.attributes.items;
    try testing.expectEqual(3, attrs.len);

    try testing.expectEqualStrings("empty", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("", attrs[0].value[0..attrs[0].value_len]);

    try testing.expectEqualStrings("also-empty", attrs[2].name[0..attrs[2].name_len]);
    try testing.expectEqualStrings("", attrs[2].value[0..attrs[2].value_len]);
}

test "test_malformed_recovery" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><unclosed>content<closed></closed></root>";
    try parser.write(input);

    const tags = handler.tags.items;
    try testing.expect(tags.len >= 2);
}

test "test_unicode_content" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root>Unicode: café, 测试, 🌟</root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(1, texts.len);

    const content = texts[0].value[0..(texts[0].header[1] - texts[0].header[0])];
    try testing.expectEqualStrings("Unicode: café, 测试, 🌟", content);
}

test "test_namespace_prefixes" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<ns:root xmlns:ns=\"http://example.com\"><ns:child ns:attr=\"value\">content</ns:child></ns:root>";
    try parser.write(input);

    const tags = handler.tags.items;
    const attrs = handler.attributes.items;

    try testing.expectEqualStrings("ns:root", tags[0].name[0..tags[0].name_len]);
    try testing.expectEqualStrings("ns:child", tags[1].name[0..tags[1].name_len]);

    try testing.expect(attrs.len >= 2);
}

test "test_large_content" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    var large_content = std.ArrayList(u8).init(allocator);
    defer large_content.deinit();

    try large_content.appendSlice("<root>");
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try large_content.appendSlice("<item>content</item>");
    }
    try large_content.appendSlice("</root>");

    try parser.write(large_content.items);

    const tags = handler.tags.items;
    try testing.expectEqual(2002, tags.len);
}

test "test_position_tracking" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input =
        \\<root>
        \\  <element>content</element>
        \\</root>
    ;
    try parser.write(input);

    const tags = handler.tags.items;
    try testing.expect(tags[0].start.line == 1);
    try testing.expect(tags[1].start.line == 2);
}

test "test_mixed_content" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root>Text before <child>nested</child> text after <another>more</another> final text</root>";
    try parser.write(input);

    const texts = handler.texts.items;
    const tags = handler.tags.items;

    try testing.expect(texts.len >= 4);
    try testing.expect(tags.len == 6);
}

test "attribute unquoted hypenated attribute" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<element data-test=\"value with spaces\" hyphen-attr=\"test\" under_score=\"test\" number123=\"test\"></element>";
    try parser.write(input);

    const attrs = handler.attributes.items;
    try testing.expectEqual(4, attrs.len);

    try testing.expectEqualStrings("data-test", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("value with spaces", attrs[0].value[0..attrs[0].value_len]);

    try testing.expectEqualStrings("hyphen-attr", attrs[1].name[0..attrs[1].name_len]);
    try testing.expectEqualStrings("test", attrs[1].value[0..attrs[1].value_len]);

    try testing.expectEqualStrings("under_score", attrs[2].name[0..attrs[2].name_len]);
    try testing.expectEqualStrings("test", attrs[2].value[0..attrs[2].value_len]);

    try testing.expectEqualStrings("number123", attrs[3].name[0..attrs[3].name_len]);
    try testing.expectEqualStrings("test", attrs[3].value[0..attrs[3].value_len]);
}
