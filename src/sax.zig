const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SaxEventType = enum(c_int) {
  Open = 0,
  Close = 1,
  Text = 2,
  Comment = 3,
  ProcessingInstruction = 4,
  Cdata = 5,
};

// SaxEvent as an extern struct
pub const SaxEvent = extern struct {
    type: SaxEventType,
    name: Slice,
    attributes: SliceAttributes,

    pub const Slice = extern struct {
        ptr: [*]const u8,
        len: usize,
    };

    pub const SliceAttributes = extern struct {
        ptr: ?[*]const Attribute, // Changed to optional pointer
        len: usize,
    };
};

// Attribute must be extern for C compatibility
pub const Attribute = extern struct {
    name: SaxEvent.Slice,
    value: SaxEvent.Slice,
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
    attributes: std.ArrayList(Attribute),
    context: ?*anyopaque,
    on_event: ?*const fn (?*anyopaque, SaxEvent) callconv(.C) void,

    pub fn init(allocator: Allocator, context: ?*anyopaque, callback: ?*const fn (?*anyopaque, SaxEvent) callconv(.C) void) !SaxParser {
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
            .attributes = std.ArrayList(Attribute).init(allocator),
            .context = context,
            .on_event = callback,
        };
    }

    pub fn deinit(self: *SaxParser) void {
        self.attributes.deinit();
    }

    pub fn write(self: *SaxParser, input: []const u8) void {
        self.buffer = input;
        self.pos = 0;
        var record_start: usize = 0;

        while (self.pos < self.buffer.len) : (self.pos += 1) {
            const c = self.buffer[self.pos];

            switch (self.state) {
                .Text => {
                    if (c == '<') {
                        if (self.pos > record_start) {
                            const text = self.buffer[record_start..self.pos];
                            const event = SaxEvent{
                                .type = .Text,
                                .name = .{ .ptr = text.ptr, .len = text.len },
                                .attributes = .{ .ptr = null, .len = 0 },
                            };
                            std.debug.print("Emitting Text event: type={} data={s}\n", .{ @intFromEnum(event.type), text });
                            if (self.on_event != null) {
                                self.on_event.?(self.context, event);
                            }
                        }
                        self.state = if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '!') .IgnoreComment else if (self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '?') .IgnoreInstruction else .TagName;
                        self.end_tag = false;
                        self.self_closing = false;
                        record_start = self.pos + 1;
                        if (self.state == .IgnoreComment and self.pos + 3 < self.buffer.len and
                            std.mem.eql(u8, self.buffer[self.pos + 1 .. self.pos + 4], "!--"))
                        {
                            self.pos += 3; // Skip past <!--
                            // Skip leading hyphens and whitespace
                            while (self.pos < self.buffer.len and
                                (self.buffer[self.pos] == '-' or
                                    self.buffer[self.pos] == ' ' or
                                    self.buffer[self.pos] == '\t' or
                                    self.buffer[self.pos] == '\n' or
                                    self.buffer[self.pos] == '\r')) : (self.pos += 1)
                            {}
                            if (self.pos < self.buffer.len) {
                                record_start = self.pos; // Start at first non-hyphen, non-whitespace character
                            } else {
                                record_start = self.pos; // Handle empty comment case
                            }
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
                            self.pos += 8; // Skip past <![CDATA[
                            record_start = self.pos + 1; // Start at the first character of actual CDATA content
                        }
                    }
                },
                .IgnoreComment => {
                    if (self.pos + 2 < self.buffer.len and
                        std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "-->"))
                    {
                        const comment = self.buffer[record_start..self.pos];
                        // Trim trailing whitespace
                        const trimmed_comment = std.mem.trimRight(u8, comment, " \t\n\r");
                        const event = SaxEvent{
                            .type = .Comment,
                            .name = .{ .ptr = trimmed_comment.ptr, .len = trimmed_comment.len },
                            .attributes = .{ .ptr = null, .len = 0 },
                        };
                        std.debug.print("Emitting Comment event: type={} data={s}\n", .{ @intFromEnum(event.type), trimmed_comment });
                        if (self.on_event != null) {
                            self.on_event.?(self.context, event);
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
                        const pi = self.buffer[record_start..self.pos];
                        const event = SaxEvent{
                            .type = .ProcessingInstruction,
                            .name = .{ .ptr = pi.ptr, .len = pi.len },
                            .attributes = .{ .ptr = null, .len = 0 },
                        };
                        std.debug.print("Emitting ProcessingInstruction event: type={} data={s}\n", .{ @intFromEnum(event.type), pi });
                        if (self.on_event != null) {
                            self.on_event.?(self.context, event);
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
                        if (self.end_tag) {
                            const event = SaxEvent{
                                .type = .Close,
                                .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                .attributes = .{ .ptr = null, .len = 0 },
                            };
                            std.debug.print("Emitting Close event: type={} data={s}\n", .{ @intFromEnum(event.type), self.tag_name });
                            if (self.on_event != null) {
                                self.on_event.?(self.context, event);
                            }
                        } else {
                            const event = SaxEvent{
                                .type = .Open,
                                .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                .attributes = .{ .ptr = self.attributes.items.ptr, .len = self.attributes.items.len },
                            };
                            std.debug.print("Emitting Open event: type={} data={s}\n", .{ @intFromEnum(event.type), self.tag_name });
                            if (self.on_event != null) {
                                self.on_event.?(self.context, event);
                            }
                            if (self.self_closing) {
                                const close_event = SaxEvent{
                                    .type = .Close,
                                    .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                    .attributes = .{ .ptr = null, .len = 0 },
                                };
                                std.debug.print("Emitting Close event (self-closing): type={} data={s}\n", .{ @intFromEnum(close_event.type), self.tag_name });
                                if (self.on_event != null) {
                                    self.on_event.?(self.context, close_event);
                                }
                            }
                        }
                        self.attributes.clearRetainingCapacity();
                        self.state = .Text;
                        record_start = self.pos + 1;
                    }
                },
                .Tag => {
                    if (c == '/') {
                        self.self_closing = true;
                        record_start = self.pos + 1;
                    } else if (c == '>') {
                        if (self.end_tag) {
                            const event = SaxEvent{
                                .type = .Close,
                                .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                .attributes = .{ .ptr = null, .len = 0 },
                            };
                            std.debug.print("Emitting Close event: type={} data={s}\n", .{ @intFromEnum(event.type), self.tag_name });
                            if (self.on_event != null) {
                                self.on_event.?(self.context, event);
                            }
                        } else {
                            const event = SaxEvent{
                                .type = .Open,
                                .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                .attributes = .{ .ptr = self.attributes.items.ptr, .len = self.attributes.items.len },
                            };
                            std.debug.print("Emitting Open event: type={} data={s}\n", .{ @intFromEnum(event.type), self.tag_name });
                            if (self.on_event != null) {
                                self.on_event.?(self.context, event);
                            }
                            if (self.self_closing) {
                                const close_event = SaxEvent{
                                    .type = .Close,
                                    .name = .{ .ptr = self.tag_name.ptr, .len = self.tag_name.len },
                                    .attributes = .{ .ptr = null, .len = 0 },
                                };
                                std.debug.print("Emitting Close event (self-closing): type={} data={s}\n", .{ @intFromEnum(close_event.type), self.tag_name });
                                if (self.on_event != null) {
                                    self.on_event.?(self.context, close_event);
                                }
                            }
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
                    } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        self.state = .Tag;
                        record_start = self.pos + 1;
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
                        self.attributes.append(.{ .name = .{ .ptr = self.attr_name.ptr, .len = self.attr_name.len }, .value = .{ .ptr = self.attr_value.ptr, .len = self.attr_value.len } }) catch {
                            std.debug.print("Failed to append attribute: {s}={s}\n", .{ self.attr_name, self.attr_value });
                        };
                        self.state = .Tag;
                        record_start = self.pos + 1;
                    }
                },
                .AttrValue => {},
                .Cdata => {
                    if (self.pos + 2 < self.buffer.len and
                        std.mem.eql(u8, self.buffer[self.pos .. self.pos + 3], "]]>"))
                    {
                        const cdata = self.buffer[record_start..self.pos];
                        const event = SaxEvent{
                            .type = .Cdata,
                            .name = .{ .ptr = cdata.ptr, .len = cdata.len },
                            .attributes = .{ .ptr = null, .len = 0 },
                        };
                        std.debug.print("Emitting Cdata event: type={} data={s}\n", .{ @intFromEnum(event.type), cdata });
                        if (self.on_event != null) {
                            self.on_event.?(self.context, event);
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

// Example FFI interface for Bun
pub export fn create_parser(allocator: *std.mem.Allocator, context: ?*anyopaque, callback: ?*const fn (?*anyopaque, SaxEvent) callconv(.C) void) ?*SaxParser {
    const parser = allocator.create(SaxParser) catch return null;
    parser.* = SaxParser.init(allocator.*, context, callback) catch return null;
    return parser;
}

pub export fn destroy_parser(parser: *SaxParser) void {
    parser.deinit();
    parser.allocator.destroy(parser);
}

pub export fn parse(parser: *SaxParser, input: [*]const u8, len: usize) void {
    parser.write(input[0..len]);
}

// Testing

const testing = std.testing;

const EventCapture = struct {
    events: std.ArrayList(SaxEvent),

    fn init(allocator: Allocator) EventCapture {
        return .{ .events = std.ArrayList(SaxEvent).init(allocator) };
    }

    fn deinit(self: *EventCapture) void {
        // Free attributes for each event
        for (self.events.items) |event| {
            if (event.attributes.len > 0 and event.attributes.ptr != null) {
                self.events.allocator.free(event.attributes.ptr.?[0..event.attributes.len]);
            }
        }
        self.events.deinit();
    }

    fn handle(context: ?*anyopaque, event: SaxEvent) callconv(.C) void {
        // Cast context back to *EventCapture
        const self = @as(*EventCapture, @ptrCast(@alignCast(context orelse return)));
        // Create a copy of the event to store
        const event_copy = SaxEvent{
            .type = event.type,
            .name = .{ .ptr = event.name.ptr, .len = event.name.len },
            .attributes = .{
                .ptr = if (event.attributes.len > 0) blk: {
                    const attrs = self.events.allocator.alloc(Attribute, event.attributes.len) catch return;
                    for (event.attributes.ptr.?[0..event.attributes.len], 0..) |attr, i| {
                        attrs[i] = Attribute{
                            .name = .{ .ptr = attr.name.ptr, .len = attr.name.len },
                            .value = .{ .ptr = attr.value.ptr, .len = attr.value.len },
                        };
                    }
                    break :blk attrs.ptr;
                } else null,
                .len = event.attributes.len,
            },
        };
        self.events.append(event_copy) catch return;
    }
};

test "SaxParser processes XML input correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Initialize event capture
    var capture = EventCapture.init(alloc);
    defer capture.deinit();

    // Initialize parser with the capture handler
    var parser = try SaxParser.init(alloc, &capture, EventCapture.handle);
    defer parser.deinit();

    // Input XML (same as in original main)
    const input =
        "<?xml version=\"1.0\"?>\n" ++
        "<book id=\"123\" lang=\"en\">\n" ++
        "  <!-- This is a comment -->\n" ++
        "  <title>Hello World</title>\n" ++
        "  <![CDATA[Some <b>CDATA</b> content]]>\n" ++
        "</book>";

    // Parse the input
    parser.write(input);

    // Expected events, including whitespace Text events
    const expected_events = [_]struct {
        event_type: SaxEventType,
        name: []const u8,
        attributes: []const struct { name: []const u8, value: []const u8 } = &.{},
    }{
        .{ .event_type = .ProcessingInstruction, .name = "xml version=\"1.0\"" },
        .{ .event_type = .Text, .name = "\n" }, // Whitespace after PI
        .{ .event_type = .Open, .name = "book", .attributes = &.{
            .{ .name = "id", .value = "123" },
            .{ .name = "lang", .value = "en" },
        } },
        .{ .event_type = .Text, .name = "\n  " }, // Whitespace before comment
        .{ .event_type = .Comment, .name = "This is a comment" },
        .{ .event_type = .Text, .name = "\n  " }, // Whitespace after comment
        .{ .event_type = .Open, .name = "title" },
        .{ .event_type = .Text, .name = "Hello World" },
        .{ .event_type = .Close, .name = "title" },
        .{ .event_type = .Text, .name = "\n  " }, // Whitespace after title
        .{ .event_type = .Cdata, .name = "Some <b>CDATA</b> content" },
        .{ .event_type = .Text, .name = "\n" }, // Whitespace after CDATA
        .{ .event_type = .Close, .name = "book" },
    };

    // Verify the number of events
    try testing.expectEqual(expected_events.len, capture.events.items.len);

    // Verify each event
    for (expected_events, capture.events.items, 0..expected_events.len) |expected, actual, _| {
        // Check event type
        try testing.expectEqual(expected.event_type, actual.type);

        // Check event name
        const actual_name = actual.name.ptr[0..actual.name.len];
        try testing.expectEqualStrings(expected.name, actual_name);

        // Check attributes
        try testing.expectEqual(expected.attributes.len, actual.attributes.len);
        if (expected.attributes.len > 0) {
            const actual_attrs = actual.attributes.ptr.?[0..actual.attributes.len];
            for (expected.attributes, actual_attrs, 0..expected.attributes.len) |exp_attr, act_attr, _| {
                const act_attr_name = act_attr.name.ptr[0..act_attr.name.len];
                const act_attr_value = act_attr.value.ptr[0..act_attr.value.len];
                try testing.expectEqualStrings(exp_attr.name, act_attr_name);
                try testing.expectEqualStrings(exp_attr.value, act_attr_value);
            }
        }
    }
}
