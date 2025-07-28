const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Position = struct {
    line: u64,
    char: u64,
};

pub const Text = struct {
    value: []const u8,
    start: Position,
    end: Position,
    header: [2]usize,
};

pub const Attr = struct {
    name: []const u8,
    value: []const u8,
};

pub const OpenTag = struct {
    name: []const u8,
    attributes: []Attr,
    start: Position,
    end: Position,
    header: [2]usize,
};

pub const CloseTag = struct {
    name: []const u8,
    start: Position,
    end: Position,
    header: [2]usize,
};

pub const EntityType = enum {
    open_tag,
    close_tag,
    text,
    comment,
    processing_instruction,
    cdata,
};

pub const Entity = union(EntityType) {
    open_tag: OpenTag,
    close_tag: CloseTag,
    text: Text,
    comment: Text,
    processing_instruction: Text,
    cdata: Text,
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
    on_event: ?*const fn (?*anyopaque, EntityType, Entity) callconv(.C) void,
    tag_start_byte: usize,

    pub fn init(allocator: Allocator, context: ?*anyopaque, callback: ?*const fn (?*anyopaque, EntityType, Entity) callconv(.C) void) !SaxParser {
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
                            const text_header = [_]usize{ record_start, self.pos };
                            const text_value = self.buffer[text_header[0]..text_header[1]];
                            const start_pos = self.get_position(text_header[0]);
                            const end_pos = self.get_position(self.pos - 1);
                            const text_entity = Text{
                                .value = text_value,
                                .start = start_pos,
                                .end = end_pos,
                                .header = text_header,
                            };
                            const entity = Entity{ .text = text_entity };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, .text, entity);
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
                            .value = trimmed_comment,
                            .start = start_pos,
                            .end = end_pos,
                            .header = comment_header,
                        };
                        const entity = Entity{ .comment = comment_entity };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, .comment, entity);
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
                            .value = pi_value,
                            .start = start_pos,
                            .end = end_pos,
                            .header = pi_header,
                        };
                        const entity = Entity{ .processing_instruction = pi_entity };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, .processing_instruction, entity);
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
                            const close_tag = CloseTag{
                                .name = self.tag_name,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .close_tag = close_tag };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, .close_tag, entity);
                            }
                        } else {
                            const open_tag = OpenTag{
                                .name = self.tag_name,
                                .attributes = self.attributes.items,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .open_tag = open_tag };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, .open_tag, entity);
                            }
                            if (self.self_closing) {
                                const close_tag = CloseTag{
                                    .name = self.tag_name,
                                    .start = start_pos,
                                    .end = end_pos,
                                    .header = tag_header,
                                };
                                const entity2 = Entity{ .close_tag = close_tag };
                                if (self.on_event != null) {
                                    self.on_event.?(self.context, .close_tag, entity2);
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
                        const tag_header = [_]usize{ self.tag_start_byte, self.pos + 1 };
                        const start_pos = self.get_position(self.tag_start_byte);
                        const end_pos = self.get_position(self.pos);
                        if (self.end_tag) {
                            const close_tag = CloseTag{
                                .name = self.tag_name,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .close_tag = close_tag };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, .close_tag, entity);
                            }
                        } else {
                            const open_tag = OpenTag{
                                .name = self.tag_name,
                                .attributes = self.attributes.items,
                                .start = start_pos,
                                .end = end_pos,
                                .header = tag_header,
                            };
                            const entity = Entity{ .open_tag = open_tag };
                            if (self.on_event != null) {
                                self.on_event.?(self.context, .open_tag, entity);
                            }
                            if (self.self_closing) {
                                const close_tag = CloseTag{
                                    .name = self.tag_name,
                                    .start = start_pos,
                                    .end = end_pos,
                                    .header = tag_header,
                                };
                                const entity2 = Entity{ .close_tag = close_tag };
                                if (self.on_event != null) {
                                    self.on_event.?(self.context, .close_tag, entity2 );
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
                        self.attributes.append(.{ .name = self.attr_name, .value = self.attr_value }) catch {};
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
                            .value = cdata_value,
                            .start = start_pos,
                            .end = end_pos,
                            .header = cdata_header,
                        };
                        const entity = Entity{ .cdata = cdata_entity };
                        if (self.on_event != null) {
                            self.on_event.?(self.context, .cdata, entity);
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
