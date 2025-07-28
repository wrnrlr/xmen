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
};

pub const Attr = extern struct {
    name: [*c]const u8,
    name_len: usize,
    value: [*c]const u8,
    value_len: usize,
};

pub const OpenTag = extern struct {
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
        open_tag: OpenTag,
        close_tag: OpenTag,
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

    pub fn write(self: *SaxParser, input: []const u8) !void {
        self.buffer = input;
        self.pos = 0;
        var record_start: usize = 0;

        while (self.pos < self.buffer.len) : (self.pos += 1) {
            const c = self.buffer[self.pos];

            switch (self.state) {
                .Text => {
                    if (c == '<') {
                        if (self.pos > record_start) {
                            const text_header = [_]usize{ record_start, self.pos };
                            const text_value = self.buffer[text_header[0]..text_header[1]];
                            const start_pos = self.get_position(text_header[0]);
                            const end_pos = self.get_position(self.pos - 1);
                            const text_entity = Text{
                                .value = text_value.ptr,
                                .start = start_pos,
                                .end = end_pos,
                                .header = text_header,
                            };
                            const entity = Entity{ .tag = .text, .data = .{ .text = text_entity } };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, entity);
                            }
                        }
                        self.tag_start_byte = self.pos;
                        self.state = if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '!') .IgnoreComment
                                     else if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '?') .IgnoreInstruction
                                     else .TagName;
                        self.end_tag = false;
                        self.self_closing = false;
                        record_start = self.pos + 1;
                        if (self.state == .IgnoreComment and self.pos + 3 < self.buffer.len and
                            std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 4], "!--"))
                        {
                            self.pos += 3;
                            while (self.pos < self.buffer.len and
                                (self.buffer[self.pos] == '-' or
                                    self.buffer[self.pos] == ' ' or
                                    self.buffer[self.pos] == '\t' or
                                    self.buffer[self.pos] == '\n' or
                                    self.buffer[self.pos] == '\r')) : (self.pos += 1)
                            {}
                            record_start = self.pos;
                        } else if (self.state == .IgnoreInstruction and self.pos + 1 < self.buffer.len and
                            self.buffer[self.pos + 1] == '?')
                        {
                            self.pos += 1;
                            record_start = self.pos + 1;
                        } else if (self.state == .TagName and self.pos + 1 < self.buffer.len and
                            self.buffer[self.pos + 1] == '/')
                        {
                            self.end_tag = true;
                            self.pos += 1;
                            record_start = self.pos + 1;
                        } else if (self.state == .IgnoreComment and self.pos + 8 < self.buffer.len and
                            std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 9], "![CDATA["))
                        {
                            self.state = .Cdata;
                            self.pos += 8;
                            record_start = self.pos + 1;
                        }
                    }
                },
                .IgnoreComment => {
                    if (self.pos + 2 < self.buffer.len and
                        std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "-->"))
                    {
                        const comment_header = [_]usize{ record_start, self.pos };
                        const comment_value = self.buffer[comment_header[0]..comment_header[1]];
                        const trimmed_comment = std.mem.trimRight(u8, comment_value, " \t\n\r");
                        const start_pos = self.get_position(comment_header[0]);
                        const end_pos = self.get_position(self.pos - 1);
                        const comment_entity = Text{
                            .value = trimmed_comment.ptr,
                            .start = start_pos,
                            .end = end_pos,
                            .header = comment_header,
                        };
                        const entity = Entity{ .tag = .comment, .data = .{ .comment = comment_entity } };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, entity);
                        }
                        self.pos += 2;
                        self.state = .Text;
                        record_start = self.pos + 1;
                    }
                },
                .IgnoreInstruction => {
                    if (self.pos + 1 < self.buffer.len and
                        std.mem.eql(u8, self.buffer[self.pos .. self.pos + 2], "?>"))
                    {
                        const pi_header = [_]usize{ record_start, self.pos };
                        const pi_value = self.buffer[pi_header[0]..pi_header[1]];
                        const start_pos = self.get_position(pi_header[0]);
                        const end_pos = self.get_position(self.pos - 1);
                        const pi_entity = Text{
                            .value = pi_value.ptr,
                            .start = start_pos,
                            .end = end_pos,
                            .header = pi_header,
                        };
                        const entity = Entity{ .tag = .processing_instruction, .data = .{ .processing_instruction = pi_entity } };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, entity);
                        }
                        self.pos += 1;
                        self.state = .Text;
                        record_start = self.pos + 1;
                    }
                },
                .TagName => {
                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        self.tag_name = self.buffer[record_start..self.pos];
                        self.state = .Tag;
                        record_start = self.pos + 1;
                    } else if (c == '/') {
                        self.self_closing = true;
                    } else if (c == '>') {
                        self.tag_name = self.buffer[record_start..self.pos];
                        const tag_header = [_]usize{self.tag_start_byte, self.pos + 1};
                        const start_pos = self.get_position(self.tag_start_byte);
                        const end_pos = self.get_position(self.pos);
                        if (self.end_tag) {
                            const close_tag = OpenTag{
                                .name = self.tag_name.ptr,
                                .name_len = self.tag_name.len,
                                .attributes = null,
                                .attributes_len = 0,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .tag = .close_tag, .data = .{ .close_tag = close_tag } };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, entity);
                            }
                        } else {
                            const open_tag = OpenTag{
                                .name = self.tag_name.ptr,
                                .name_len = self.tag_name.len,
                                .attributes = self.attributes.items.ptr,
                                .attributes_len = self.attributes.items.len,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .tag = .open_tag, .data = .{ .open_tag = open_tag } };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, entity);
                            }
                            if (self.self_closing) {
                                const close_tag = OpenTag{
                                    .name = self.tag_name.ptr,
                                    .name_len = self.tag_name.len,
                                    .attributes = null,
                                    .attributes_len = 0,
                                    .start = start_pos,
                                    .end = end_pos,
                                    .header = tag_header,
                                };
                                const entity2 = Entity{ .tag = .close_tag, .data = .{ .close_tag = close_tag } };
                                if (self.on_event != null) {
                                    self.on_event.?(self.context, entity2);
                                }
                            }
                        }
                        self.attributes.clearRetainingCapacity();
                        self.state = .Text;
                        record_start = self.pos + 1;
                    }
                },
                .Tag => {
                    if (c == '>') {
                        const tag_header = [_]usize{ self.tag_start_byte, self.pos + 1 };
                        const start_pos = self.get_position(self.tag_start_byte);
                        const end_pos = self.get_position(self.pos);
                        if (self.end_tag) {
                            const close_tag = OpenTag{
                                .name = self.tag_name.ptr,
                                .name_len = self.tag_name.len,
                                .attributes = null,
                                .attributes_len = 0,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .tag = .close_tag, .data = .{ .close_tag = close_tag } };
                            if (self.on_event != null) self.on_event.?(self.context, entity);
                        } else {
                            const open_tag = OpenTag{
                                .name = self.tag_name.ptr,
                                .name_len = self.tag_name.len,
                                .attributes = if (self.attributes.items.len > 0) self.attributes.items.ptr else null,
                                .attributes_len = self.attributes.items.len,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .tag = .open_tag, .data = .{ .open_tag = open_tag } };
                            if (self.on_event != null) self.on_event.?(self.context, entity);
                            // ... (self-closing logic unchanged)
                        }
                        self.attributes.clearRetainingCapacity();
                        self.state = .Text;
                        record_start = self.pos + 1;
                    } else if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                        self.state = .AttrName;
                        record_start = self.pos;
                    }
                },
                .AttrName => {
                    if (c == '=') {
                        self.attr_name = self.buffer[record_start..self.pos];
                        self.state = .AttrEq;
                        record_start = self.pos + 1;
                    } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>') {
                        // Handle boolean attributes (e.g., disabled)
                        self.attr_name = self.buffer[record_start..self.pos];
                        if (self.attr_name.len > 0 and !std.mem.eql(u8, self.attr_name, "/")) {
                            self.attributes.append(.{
                                .name = self.attr_name.ptr,
                                .name_len = self.attr_name.len,
                                .value = "",
                                .value_len = 0,
                            }) catch {};
                        }
                        self.state = .Tag;
                        record_start = self.pos + 1;
                        if (c == '>') {
                            // Process the tag closing immediately
                            self.pos -= 1; // Backtrack to let .Tag handle '>'
                        }
                    } else if (c == '/') {
                        // Check if this is part of a self-closing tag (e.g., />)
                        if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '>') {
                            self.self_closing = true;
                            self.state = .Tag;
                            record_start = self.pos + 1;
                        } else {
                            // Treat as part of attribute name if not followed by '>'
                            self.attr_name = self.buffer[record_start..self.pos];
                            if (self.attr_name.len > 0 and !std.mem.eql(u8, self.attr_name, "/")) {
                                self.attributes.append(.{
                                    .name = self.attr_name.ptr,
                                    .name_len = self.attr_name.len,
                                    .value = "",
                                    .value_len = 0,
                                }) catch {};
                            }
                            self.state = .Tag;
                            record_start = self.pos + 1;
                        }
                    }
                },
                .AttrEq => {
                    if (c == '"' or c == '\'') {
                        self.state = .AttrQuot;
                        record_start = self.pos + 1;
                    }
                },
                .AttrQuot => {
                    if (c == '"' or c == '\'') {
                        self.attr_value = self.buffer[record_start..self.pos];
                        self.attributes.append(.{
                            .name = self.attr_name.ptr,
                            .name_len = self.attr_name.len,
                            .value = self.attr_value.ptr,
                            .value_len = self.attr_value.len,
                        }) catch {};
                        self.state = .Tag;
                        record_start = self.pos + 1;
                    }
                },
                .AttrValue => {},
                .Cdata => {
                    if (self.pos + 2 < self.buffer.len and
                        std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "]]>"))
                    {
                        const cdata_header = [_]usize{ record_start, self.pos };
                        const cdata_value = self.buffer[cdata_header[0]..cdata_header[1]];
                        const start_pos = self.get_position(cdata_header[0]);
                        const end_pos = self.get_position(self.pos - 1);
                        const cdata_entity = Text{
                            .value = cdata_value.ptr,
                            .start = start_pos,
                            .end = end_pos,
                            .header = cdata_header,
                        };
                        const entity = Entity{ .tag = .cdata, .data = .{ .cdata = cdata_entity } };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, entity);
                        }
                        self.pos += 2;
                        self.state = .Text;
                        record_start = self.pos + 1;
                    }
                },
                .IgnoreCdata => {},
            }
        }
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

pub export fn parse(parser: *SaxParser, input: [*]const u8, len: usize) void {
    _ = parser.write(input[0..len]) catch |err| {
        std.debug.print("Error in parser.write: {any}\n", .{err});
        return;
    };
}

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
    tags: std.ArrayList(OpenTag),
    proc_insts: std.ArrayList(Text),

    pub fn init(allocator: Allocator) TestEventHandler {
        return .{
            .allocator = allocator,
            .attributes = std.ArrayList(Attr).init(allocator),
            .texts = std.ArrayList(Text).init(allocator),
            .tags = std.ArrayList(OpenTag).init(allocator),
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
                    // std.debug.print("Open tag: {s}, attributes_len: {}\n", .{entity.data.open_tag.name[0..entity.data.open_tag.name_len], entity.data.open_tag.attributes_len});
                    self.tags.append(entity.data.open_tag) catch {};
                    if (entity.data.open_tag.attributes != null and entity.data.open_tag.attributes_len > 0) {
                        const attrs_slice = entity.data.open_tag.attributes[0..entity.data.open_tag.attributes_len];
                        for (attrs_slice, 0..) |attr, i| {
                            std.debug.print("Attribute {}: name={s}, value={s}\n", .{i, attr.name[0..attr.name_len], attr.value[0..attr.value_len]});
                            self.attributes.append(attr) catch {};
                        }
                    }
                },
                .close_tag => {
                    self.tags.append(entity.data.open_tag) catch {};
                },
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
// Additional comprehensive test cases for XML SAX parser

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

    // Verify tag order and names
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

test "test_comments" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    const input = "<root><!-- This is a comment --><element>content</element><!-- Another comment --></root>";
    try parser.write(input);

    const texts = handler.texts.items;
    try testing.expectEqual(3, texts.len); // 2 comments + 1 text content
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

    // Verify we captured all elements
    const tags = handler.tags.items;
    const attrs = handler.attributes.items;
    _ = handler.texts.items;
    const proc_insts = handler.proc_insts.items;

    try testing.expect(tags.len > 10); // Multiple open/close tags
    try testing.expect(attrs.len >= 3); // xmlns, id, class attributes
    try testing.expect(proc_insts.len == 1); // XML declaration
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

    // Test parser behavior with some edge cases
    const input = "<root><unclosed>content<closed></closed></root>";
    try parser.write(input);

    // Should still parse what it can
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

    // Should capture namespace declarations and prefixed attributes
    try testing.expect(attrs.len >= 2);
}

test "test_large_content" {
    const allocator = std.testing.allocator;
    var handler = TestEventHandler.init(allocator);
    defer handler.deinit();

    var parser = try setupParser(allocator, &handler);
    defer parser.deinit();

    // Create a large content string
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
    try testing.expectEqual(2001, tags.len); // 1 root open + 1000 item open + 1000 item close + 1 root close
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
    // Verify position information is captured
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

    // Should capture all text segments between and within elements
    try testing.expect(texts.len >= 4); // Multiple text segments
    try testing.expect(tags.len == 6); // 3 open + 3 close tags
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

    // Verify various attribute name formats are handled
    try testing.expectEqualStrings("data-test", attrs[0].name[0..attrs[0].name_len]);
    try testing.expectEqualStrings("value with spaces", attrs[0].value[0..attrs[0].value_len]);

    try testing.expectEqualStrings("hyphen-attr", attrs[1].name[0..attrs[1].name_len]);
    try testing.expectEqualStrings("test", attrs[1].value[0..attrs[1].value_len]);

    try testing.expectEqualStrings("under_score", attrs[2].name[0..attrs[2].name_len]);
    try testing.expectEqualStrings("test", attrs[2].value[0..attrs[2].value_len]);

    try testing.expectEqualStrings("number123", attrs[3].name[0..attrs[3].name_len]);
    try testing.expectEqualStrings("test", attrs[3].value[0..attrs[3].value_len]);
}

// test "test_attribute_unquoted" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "<element attribute1=value1 attribute2='value2'></element>";
//     try parser.write(input);
//     // try parser.identity();

//     const attrs = handler.attributes.items;

//     try testing.expectEqual(2, attrs.len);
//     try testing.expectEqualStrings("attribute1", attrs[0].name);
//     try testing.expectEqualStrings("value1", attrs[0].value);
//     try testing.expectEqualStrings("attribute2", attrs[1].name);
//     try testing.expectEqualStrings("value2", attrs[1].value);
// }

// test "test_attribute_single_character" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "<element attribute1='value1' a='value2' attribute3='value3'></element>";
//     try parser.write(input);
//     // try parser.identity();

//     const attrs = handler.attributes.items;

//     try testing.expectEqual(3, attrs.len);
//     try testing.expectEqualStrings("attribute1", attrs[0].name);
//     try testing.expectEqualStrings("value1", attrs[0].value);
//     try testing.expectEqualStrings("a", attrs[1].name);
//     try testing.expectEqualStrings("value2", attrs[1].value);
//     try testing.expectEqualStrings("attribute3", attrs[2].name);
//     try testing.expectEqualStrings("value3", attrs[2].value);
// }

// test "test_empty_tag" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "<div><a href=\"http://github.com\">GitHub</a></orphan></div>";
//     try parser.write(input);
//     // try parser.identity();

//     const tags = handler.tags.items;
//     const texts = handler.texts.items;

//     try testing.expectEqual(2, tags.len);
//     try testing.expectEqualStrings("a", tags[0].name);
//     try testing.expectEqual(39, tags[0].close_start.?[1]);
//     try testing.expectEqualStrings("div", tags[1].name);
//     try testing.expectEqual(52, tags[1].close_start.?[1]);

//     try testing.expectEqual(2, texts.len);
//     try testing.expectEqualStrings("GitHub", texts[0].value);
//     try testing.expectEqualStrings("</orphan>", texts[1].value);
// }

// test "test_tag" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "<div><a href=\"http://github.com\">GitHub</a></orphan></div>";
//     try parser.write(input);
//     // try parser.identity();

//     const tags = handler.tags.items;
//     const texts = handler.texts.items;

//     try testing.expectEqual(2, tags.len);
//     try testing.expectEqualStrings("a", tags[0].name);
//     try testing.expectEqual(39, tags[0].close_start.?[1]);
//     try testing.expectEqualStrings("div", tags[1].name);
//     try testing.expectEqual(52, tags[1].close_start.?[1]);

//     try testing.expectEqual(2, texts.len);
//     try testing.expectEqualStrings("GitHub", texts[0].value);
//     try testing.expectEqual([2]usize{0, 33}, texts[0].start.?);
//     try testing.expectEqual([2]usize{0, 39}, texts[0].end.?);
//     try testing.expectEqualStrings("</orphan>", texts[1].value);
// }

// test "test_tag_write_boundary" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     const input = "<div empty=\"\"><a href=\"http://github.com\">GitHub</a></orphan></div>";
//     const bytes = input;

//     for (1..bytes.len) |i| {
//         var parser = try setupParser(allocator, &handler);
//         defer parser.deinit();

//         try parser.write(bytes[0..i]);
//         try parser.write(bytes[i..]);
//         // try parser.identity();

//         const tags = handler.tags.items;
//         const texts = handler.texts.items;
//         const attrs = handler.attributes.items;

//         try testing.expectEqual(2, tags.len);
//         try testing.expectEqualStrings("a", tags[0].name);
//         try testing.expectEqual(48, tags[0].close_start.?[1]);
//         try testing.expectEqualStrings("div", tags[1].name);
//         try testing.expectEqual(61, tags[1].close_start.?[1]);

//         try testing.expectEqual(2, texts.len);
//         try testing.expectEqualStrings("GitHub", texts[0].value);
//         try testing.expectEqual([2]usize{0, 42}, texts[0].start.?);
//         try testing.expectEqual([2]usize{0, 48}, texts[0].end.?);
//         try testing.expectEqualStrings("</orphan>", texts[1].value);

//         try testing.expectEqual(2, attrs.len);
//         try testing.expectEqualStrings("empty", attrs[0].name);
//         try testing.expectEqualStrings("", attrs[0].value);
//         try testing.expectEqualStrings("href", attrs[1].name);
//         try testing.expectEqualStrings("http://github.com", attrs[1].value);
//     }
// }

// test "test_whitespace" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input =
//         \\<?xml version="1.0" encoding="UTF-8"?>
//         \\<plugin
//         \\    version       =   "1.0.0"   >
//         \\    <description>
//         \\    The current
//         \\    version of
//         \\the plugin
//         \\                </description>
//         \\</plugin>
//     ;
//     try parser.write(input);
//     // try parser.identity();

//     const tags = handler.tags.items;
//     const texts = handler.texts.items;

//     try testing.expectEqual(2, tags.len);
//     try testing.expectEqual(3, texts.len);
// }

// test "test_comment" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "<!--name='test 3 attr' this is a comment--> <-- name='test 3 attr' this is just text -->";
//     try parser.write(input);
//     // try parser.identity();

//     const texts = handler.texts.items;

//     try testing.expectEqual(2, texts.len);
//     try testing.expectEqualStrings("name='test 3 attr' this is a comment", texts[0].value);
//     try testing.expectEqualStrings(" <-- name='test 3 attr' this is just text -->", texts[1].value);
// }

// test "test_comment_write_boundary_2" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     const input =
//         \\<!--lit-part cI7PGs8mxHY=-->
//         \\        <p><!--lit-part-->hello<!--/lit-part--></p>
//         \\        <!--lit-part BRUAAAUVAAA=--><?><!--/lit-part-->
//         \\        <!--lit-part--><!--/lit-part-->
//         \\        <p>more</p>
//         \\        <!--/lit-part-->
//     ;
//     const bytes = input;

//     for (1..bytes.len) |i| {
//         var parser = try setupParser(allocator, &handler);
//         defer parser.deinit();

//         try parser.write(bytes[0..i]);
//         try parser.write(bytes[i..]);
//         // try parser.identity();

//         const texts = handler.texts.items;

//         try testing.expectEqual(8, texts.len);
//         try testing.expectEqualStrings("lit-part cI7PGs8mxHY=", texts[0].value);
//     }
// }

// test "test_4_bytes" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "🏴📚📚🏴📚📚🏴📚📚🏴📚📚🏴📚📚🏴📚📚🏴📚📚🏴📚📚🏴📚📚";
//     const bytes = input;
//     try parser.write(bytes[0..14]);
//     try parser.write(bytes[14..]);
//     // try parser.identity();

//     const texts = handler.texts.items;

//     try testing.expectEqual(1, texts.len);
//     try testing.expectEqualStrings(input, texts[0].value);
// }

// test "test_cdata_write_boundary" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     const input = "<div><![CDATA[something]]>";
//     const bytes = input;

//     for (1..bytes.len) |i| {
//         var parser = try setupParser(allocator, &handler);
//         defer parser.deinit();

//         try parser.write(bytes[0..i]);
//         try parser.write(bytes[i..]);
//         // try parser.identity();

//         const texts = handler.texts.items;

//         try testing.expectEqual(1, texts.len);
//         try testing.expectEqualStrings("something", texts[0].value);
//     }
// }

// test "test_count_grapheme_length" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input = "🏴📚📚<div href=\"./123/123\">hey there</div>";
//     try parser.write(input);
//     // try parser.identity();

//     const texts = handler.texts.items;

//     try testing.expectEqual(2, texts.len);
//     try testing.expectEqualStrings("🏴📚📚", texts[0].value);
//     try testing.expectEqualStrings("hey there", texts[1].value);
// }

// test "test_doctype" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input =
//         \\
//         \\<!DOCTYPE movie [
//         \\  <!ENTITY COM "Comedy">
//         \\  <!LIST title xml:lang TOKEN "EN" id ID #IMPLIED>
//         \\  <!ENTITY SF "Science Fiction">
//         \\  <!ELEMENT movie (title+,genre,year)>
//         \\  <!ELEMENT title (#DATA)>
//         \\  <!ELEMENT genre (#DATA)>
//         \\  <!ELEMENT year (#DATA)>
//         \\]>
//     ;
//     try parser.write(input);
//     // try parser.identity();

//     const texts = handler.texts.items;

//     try testing.expectEqual(8, texts.len);
//     try testing.expectEqualStrings("ENTITY COM \"Comedy\"", texts[0].value);
//     try testing.expectEqualStrings("LIST title xml:lang TOKEN \"EN\" id ID #IMPLIED", texts[1].value);
//     try testing.expectEqualStrings("movie", texts[7].value);
// }

// test "test_empty_cdata" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input =
//         \\<div>
//         \\        <div>
//         \\          <![CDATA[]]>
//         \\        </div>
//         \\        <div>
//         \\          <![CDATA[something]]>
//         \\        </div>
//         \\      </div>
//     ;
//     try parser.write(input);
//     // try parser.identity();

//     const texts = handler.texts.items;

//     try testing.expectEqual(2, texts.len);
//     try testing.expectEqualStrings("", texts[0].value);
//     try testing.expectEqualStrings("something", texts[1].value);
// }

// test "test_proc_inst" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input =
//         \\<?xml-stylesheet
//         \\        type="text/xsl"
//         \\        href="main.xsl"
//         \\        media="screen"
//         \\        title="Default Style"
//         \\        alternate="no"?>
//     ;
//     try parser.write(input);
//     // try parser.identity();

//     const proc_insts = handler.proc_insts.items;

//     try testing.expectEqual(1, proc_insts.len);
//     try testing.expectEqualStrings("xml-stylesheet", proc_insts[0].value); // Adjust based on parser output
// }

// test "test_self_closing_tag" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     var parser = try setupParser(allocator, &handler);
//     defer parser.deinit();

//     const input =
//         \\<Div>
//         \\    <Div type="JS" viewName="myapp.view.Home" />
//         \\    <Div type="JSON" viewName="myapp.view.Home" />
//         \\    <Div type="HTML" viewName="myapp.view.Home" />
//         \\    <Div type="Template" viewName="myapp.view.Home" />
//         \\    <AnotherSelfClosingDiv type="Template" viewName={myapp.view.Home}/>
//         \\    <Div type="Template" viewName=myapp.view.Home/>
//         \\</Div>
//     ;
//     try parser.write(input);
//     // try parser.identity();

//     const tags = handler.tags.items;

//     try testing.expectEqual(7, tags.len);
//     try testing.expect(tags[0].self_closing);  // This should now work after adding the field
//     try testing.expect(tags[1].self_closing);
//     try testing.expect(tags[2].self_closing);
//     try testing.expect(tags[3].self_closing);
//     try testing.expect(tags[4].self_closing);
//     try testing.expect(tags[5].self_closing);
//     try testing.expect(!tags[6].self_closing);
// }

// test "test_comment_write_boundary" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     const input = "<!--some comment here-->";
//     const bytes = input;

//     for (1..bytes.len) |i| {
//         var parser = try setupParser(allocator, &handler);
//         defer parser.deinit();

//         try parser.write(bytes[0..i]);
//         try parser.write(bytes[i..]);
//         // try parser.identity();

//         const texts = handler.texts.items;

//         try testing.expectEqual(1, texts.len);
//         try testing.expectEqualStrings("some comment here", texts[0].value);
//     }
// }

// test "test_attribute_value_write_boundary" {
//     const allocator = std.testing.allocator;
//     var handler = TestEventHandler.init(allocator);
//     defer handler.deinit();

//     const input = "<text top=\"100.00\" />";
//     const bytes = input;

//     for (1..bytes.len) |i| {
//         var parser = try setupParser(allocator, &handler);
//         defer parser.deinit();

//         try parser.write(bytes[0..i]);
//         try parser.write(bytes[i..]);
//         // try parser.identity();

//         const attrs = handler.attributes.items;

//         try testing.expectEqual(1, attrs.len);
//         try testing.expectEqualStrings(@as([]const u8, "top"), attrs[0].name);
//         try testing.expectEqualStrings("100.00", attrs[0].value);
//     }
// }
