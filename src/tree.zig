// XML DOM implementation
const std = @import("std");

const Allocator = std.mem.Allocator;
const NodeIndex = u32;
const StringId = u32;
const InvalidIndex: NodeIndex = 0xffffffff;
const InvalidString: StringId = 0xffffffff;

const Range = struct { start: u32, len: u32 };
const NodeKind = enum { element, text, cdata, comment, processing_instruction };

const Attribute = struct {
    name_id: StringId,
    value_id: StringId,
};

const Element = struct {
    kind: NodeKind,
    tag: ?StringId = null,
    content: ?StringId = null,
    attributes_range: Range,
    children_range: Range,
    parent: NodeIndex,
    preorder: u32,
    subtree_size: u32,
};

const Document = struct {
    root: NodeIndex,
    nodes_len: u32,
    children_len: u32,
    attributes_len: u32,
    generation: u64,
};

const EditKind = enum { ReplaceChildren, SetAttributes };

const Edit = struct {
    kind: EditKind,
    target: NodeIndex,
    children: []const NodeIndex = &[_]NodeIndex{},
    attrs: []const Attribute = &[_]Attribute{},
};

const TransformBatch = struct {
    allocator: Allocator,
    edits: std.ArrayList(Edit),

    pub fn init(allocator: Allocator) TransformBatch {
        return .{ .allocator = allocator, .edits = std.ArrayList(Edit).init(allocator) };
    }

    pub fn deinit(self: *TransformBatch) void {
        self.edits.deinit();
    }

    pub fn replaceChildren(self: *TransformBatch, target: NodeIndex, children: []const NodeIndex) !void {
        try self.edits.append(.{ .kind = .ReplaceChildren, .target = target, .children = children });
    }

    pub fn setAttributes(self: *TransformBatch, target: NodeIndex, attrs: []const Attribute) !void {
        try self.edits.append(.{ .kind = .SetAttributes, .target = target, .attrs = attrs });
    }
};

/// String interning system
const StringInterner = struct {
    allocator: Allocator,
    strings: std.ArrayList([]const u8),
    map: std.StringHashMap(StringId),

    pub fn init(allocator: Allocator) StringInterner {
        return .{
            .allocator = allocator,
            .strings = std.ArrayList([]const u8).init(allocator),
            .map = std.StringHashMap(StringId).init(allocator),
        };
    }

    pub fn deinit(self: *StringInterner) void {
        for (self.strings.items) |s| self.allocator.free(s);
        self.strings.deinit();
        self.map.deinit();
    }

    pub fn intern(self: *StringInterner, s: []const u8) !StringId {
        if (self.map.get(s)) |id| return id;
        const dup = try self.allocator.dupe(u8, s);
        const id: StringId = @intCast(self.strings.items.len);
        try self.strings.append(dup);
        try self.map.put(dup, id);
        return id;
    }

    pub fn get(self: *StringInterner, id: StringId) []const u8 {
        return self.strings.items[id];
    }
};

const DOM = struct {
    allocator: Allocator,
    interner: StringInterner,
    nodes: std.ArrayList(Element),
    children: std.ArrayList(NodeIndex),
    attributes: std.ArrayList(Attribute),

    pub fn init(allocator: Allocator) DOM {
        return .{
            .allocator = allocator,
            .interner = StringInterner.init(allocator),
            .nodes = std.ArrayList(Element).init(allocator),
            .children = std.ArrayList(NodeIndex).init(allocator),
            .attributes = std.ArrayList(Attribute).init(allocator),
        };
    }

    pub fn deinit(self: *DOM) void {
        self.interner.deinit();
        self.nodes.deinit();
        self.children.deinit();
        self.attributes.deinit();
    }

    pub fn addNode(self: *DOM, kind: NodeKind, tag: ?StringId, content: ?StringId, parent: NodeIndex) !NodeIndex {
        const idx: NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(.{
            .kind = kind,
            .tag = tag,
            .content = content,
            .attributes_range = .{ .start = 0, .len = 0 },
            .children_range = .{ .start = 0, .len = 0 },
            .parent = parent,
            .preorder = 0,
            .subtree_size = 1,
        });
        return idx;
    }

    pub fn createDocument(self: *DOM, root_kind: NodeKind, root_tag: ?StringId) !Document {
        const root_idx = try self.addNode(root_kind, root_tag, null, InvalidIndex);
        return .{
            .root = root_idx,
            .nodes_len = 1,
            .children_len = 0,
            .attributes_len = 0,
            .generation = 1,
        };
    }

    pub fn applyBatch(self: *DOM, doc: Document, batch: *TransformBatch) !Document {
        var cur_doc = doc;
        for (batch.edits.items) |edit| {
            switch (edit.kind) {
                .ReplaceChildren => {
                    cur_doc = try self.replaceChildren(cur_doc, edit.target, edit.children);
                },
                .SetAttributes => {
                    cur_doc = try self.setAttributes(cur_doc, edit.target, edit.attrs);
                },
            }
        }
        return cur_doc;
    }

    fn setAttributes(self: *DOM, doc: Document, node: NodeIndex, attrs: []const Attribute) !Document {
        const new_start: u32 = @intCast(self.attributes.items.len);
        try self.attributes.appendSlice(attrs);

        var new_node = self.nodes.items[node];
        new_node.attributes_range = .{ .start = new_start, .len = @intCast(attrs.len) };
        try self.nodes.append(new_node);

        return .{
            .root = doc.root,
            .nodes_len = @intCast(self.nodes.items.len),
            .children_len = doc.children_len,
            .attributes_len = @intCast(self.attributes.items.len),
            .generation = doc.generation + 1,
        };
    }

    fn replaceChildren(
        self: *DOM,
        doc: Document,
        parent: NodeIndex,
        new_children: []const NodeIndex,
    ) !Document {
        const new_start: u32 = @intCast(self.children.items.len);
        try self.children.appendSlice(new_children);

        var new_parent = self.nodes.items[parent];
        new_parent.children_range = .{ .start = new_start, .len = @intCast(new_children.len) };
        const new_parent_idx: NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(new_parent);

        var cur = parent;
        var new_child_idx = new_parent_idx;
        while (true) {
            const p = self.nodes.items[cur].parent;
            if (p == InvalidIndex) break;

            const pnode = self.nodes.items[p];
            const slice_start = pnode.children_range.start;
            const slice_len = pnode.children_range.len;

            const new_slice_start: u32 = @intCast(self.children.items.len);
            for (self.children.items[slice_start .. slice_start + slice_len]) |child| {
                if (child == cur) {
                    try self.children.append(new_child_idx);
                } else {
                    try self.children.append(child);
                }
            }

            var new_pnode = pnode;
            new_pnode.children_range = .{ .start = new_slice_start, .len = slice_len };
            const new_p_idx: NodeIndex = @intCast(self.nodes.items.len);
            try self.nodes.append(new_pnode);

            new_child_idx = new_p_idx;
            cur = p;
        }

        _ = try self.updatePreorder(new_child_idx, 0);

        return .{
            .root = new_child_idx,
            .nodes_len = @intCast(self.nodes.items.len),
            .children_len = @intCast(self.children.items.len),
            .attributes_len = @intCast(self.attributes.items.len),
            .generation = doc.generation + 1,
        };
    }

    fn updatePreorder(self: *DOM, node_idx: NodeIndex, start: u32) !u32 {
        var stack = std.ArrayList(NodeIndex).init(self.allocator);
        defer stack.deinit();

        try stack.append(node_idx);
        var next_preorder = start;

        while (stack.pop()) |idx| {
            var node = &self.nodes.items[idx];
            node.preorder = next_preorder;
            next_preorder += 1;

            const cr = node.children_range;
            var i = cr.len;
            while (i > 0) : (i -= 1) {
                const c = self.children.items[cr.start + i - 1];
                try stack.append(c);
            }
        }

        _ = self.computeSubtreeSize(node_idx);

        return next_preorder;
    }

    fn computeSubtreeSize(self: *DOM, node_idx: NodeIndex) u32 {
        var size: u32 = 1;
        const cr = self.nodes.items[node_idx].children_range;
        for (self.children.items[cr.start .. cr.start + cr.len]) |c| {
            size += self.computeSubtreeSize(c);
        }
        self.nodes.items[node_idx].subtree_size = size;
        return size;
    }
};

const sax = @import("sax.zig");
const SaxParser = sax.SaxParser;
const Entity = sax.Entity;

const MutableNode = struct {
    kind: NodeKind,
    u: U,

    const U = union(enum) {
        element: struct {
            tag: StringId,
            attributes: std.ArrayList(Attribute),
            children: std.ArrayList(*MutableNode),
        },
        text: struct { content: StringId },
        cdata: struct { content: StringId },
        comment: struct { content: StringId },
        processing_instruction: struct { target: StringId, content: ?StringId },
    };

    pub fn initElement(allocator: Allocator, tag: StringId) !*MutableNode {
        const self = try allocator.create(MutableNode);
        self.* = .{
            .kind = .element,
            .u = .{ .element = .{
                .tag = tag,
                .attributes = std.ArrayList(Attribute).init(allocator),
                .children = std.ArrayList(*MutableNode).init(allocator),
            } },
        };
        return self;
    }

    pub fn initText(allocator: Allocator, content: StringId) !*MutableNode {
        const self = try allocator.create(MutableNode);
        self.* = .{
            .kind = .text,
            .u = .{ .text = .{ .content = content } },
        };
        return self;
    }

    pub fn initCData(allocator: Allocator, content: StringId) !*MutableNode {
        const self = try allocator.create(MutableNode);
        self.* = .{
            .kind = .cdata,
            .u = .{ .cdata = .{ .content = content } },
        };
        return self;
    }

    pub fn initComment(allocator: Allocator, content: StringId) !*MutableNode {
        const self = try allocator.create(MutableNode);
        self.* = .{
            .kind = .comment,
            .u = .{ .comment = .{ .content = content } },
        };
        return self;
    }

    pub fn initPI(allocator: Allocator, target: StringId, content: ?StringId) !*MutableNode {
        const self = try allocator.create(MutableNode);
        self.* = .{
            .kind = .processing_instruction,
            .u = .{ .processing_instruction = .{ .target = target, .content = content } },
        };
        return self;
    }

    pub fn deinit(self: *MutableNode, allocator: Allocator) void {
        switch (self.kind) {
            .element => {
                for (self.u.element.children.items) |child| {
                    child.deinit(allocator);
                    allocator.destroy(child);
                }
                self.u.element.children.deinit();
                self.u.element.attributes.deinit();
            },
            else => {},
        }
    }
};

const DomParser = struct {
    allocator: Allocator,
    dom: *DOM,
    stack: std.ArrayList(*MutableNode),
    root: ?*MutableNode = null,
    parse_error: ?anyerror = null,

    pub fn init(allocator: Allocator, dom: *DOM) DomParser {
        return .{
            .allocator = allocator,
            .dom = dom,
            .stack = std.ArrayList(*MutableNode).init(allocator),
        };
    }

    pub fn deinit(self: *DomParser) void {
        self.stack.deinit();
        if (self.root) |r| {
            r.deinit(self.allocator);
            self.allocator.destroy(r);
        }
    }

    pub fn handleEvent(self: *DomParser, entity: Entity) !void {
        switch (entity.tag) {
            .open_tag => {
                const tag_data = entity.data.open_tag;
                const tag_str = tag_data.name[0..tag_data.name_len];
                const tag_id = try self.dom.interner.intern(tag_str);

                const node = try MutableNode.initElement(self.allocator, tag_id);
                errdefer self.allocator.destroy(node);

                for (0..tag_data.attributes_len) |i| {
                    const attr = tag_data.attributes[i];
                    const name_str = attr.name[0..attr.name_len];
                    const value_str = attr.value[0..attr.value_len];
                    const name_id = try self.dom.interner.intern(name_str);
                    const value_id = try self.dom.interner.intern(value_str);
                    try node.u.element.attributes.append(.{ .name_id = name_id, .value_id = value_id });
                }

                if (self.root == null) {
                    self.root = node;
                } else if (self.stack.items.len > 0) {
                    try self.stack.items[self.stack.items.len - 1].u.element.children.append(node);
                } else {
                    return error.MultipleRoots;
                }
                try self.stack.append(node);
            },
            .close_tag => {
                if (self.stack.items.len == 0) {
                    return error.UnexpectedCloseTag;
                }
                const tag_data = entity.data.close_tag;
                const tag_str = tag_data.name[0..tag_data.name_len];
                const actual_name = if (tag_str.len > 0 and tag_str[0] == '/') tag_str[1..] else tag_str;
                const expected_tag_id = try self.dom.interner.intern(actual_name);
                const current_node = self.stack.items[self.stack.items.len - 1];
                if (current_node.kind != .element or current_node.u.element.tag != expected_tag_id) {
                    return error.MismatchedCloseTag;
                }
                _ = self.stack.pop();
            },
            .text => {
                const text_data = entity.data.text;
                const text_str = text_data.value[0..(text_data.header[1] - text_data.header[0])];
                if (text_str.len == 0) return;
                if (self.stack.items.len == 0) return; // Ignore top-level text

                const text_id = try self.dom.interner.intern(text_str);
                const node = try MutableNode.initText(self.allocator, text_id);
                errdefer self.allocator.destroy(node);

                try self.stack.items[self.stack.items.len - 1].u.element.children.append(node);
            },
            .cdata => {
                const cdata_data = entity.data.cdata;
                const cdata_str = cdata_data.value[0..(cdata_data.header[1] - cdata_data.header[0])];
                if (cdata_str.len == 0) return;
                if (self.stack.items.len == 0) return;

                const cdata_id = try self.dom.interner.intern(cdata_str);
                const node = try MutableNode.initCData(self.allocator, cdata_id);
                errdefer self.allocator.destroy(node);

                try self.stack.items[self.stack.items.len - 1].u.element.children.append(node);
            },
            .comment => {
                const comment_data = entity.data.comment;
                const comment_str = comment_data.value[0..(comment_data.header[1] - comment_data.header[0])];
                if (comment_str.len == 0) return;
                if (self.stack.items.len == 0) return;

                const comment_id = try self.dom.interner.intern(comment_str);
                const node = try MutableNode.initComment(self.allocator, comment_id);
                errdefer self.allocator.destroy(node);

                try self.stack.items[self.stack.items.len - 1].u.element.children.append(node);
            },
            .processing_instruction => {
                const pi_data = entity.data.processing_instruction;
                const pi_str = pi_data.value[0..(pi_data.header[1] - pi_data.header[0])];
                if (pi_str.len == 0) return;
                if (self.stack.items.len == 0) return;

                var target_str: []const u8 = pi_str;
                var content_str: ?[]const u8 = null;
                if (std.mem.indexOfScalar(u8, pi_str, ' ')) |space_idx| {
                    target_str = pi_str[0..space_idx];
                    content_str = std.mem.trim(u8, pi_str[space_idx + 1 ..], " \t\r\n");
                }
                const target_id = try self.dom.interner.intern(target_str);
                const content_id = if (content_str) |cs| if (cs.len > 0) try self.dom.interner.intern(cs) else null else null;
                const node = try MutableNode.initPI(self.allocator, target_id, content_id);
                errdefer self.allocator.destroy(node);

                try self.stack.items[self.stack.items.len - 1].u.element.children.append(node);
            },
        }
    }

    pub fn build(self: *DomParser) !Document {
        if (self.root == null) return error.NoRoot;
        const root_idx = try self.freeze(self.root.?, InvalidIndex);
        _ = try self.dom.updatePreorder(root_idx, 0);
        return .{
            .root = root_idx,
            .nodes_len = @intCast(self.dom.nodes.items.len),
            .children_len = @intCast(self.dom.children.items.len),
            .attributes_len = @intCast(self.dom.attributes.items.len),
            .generation = 1,
        };
    }

    fn freeze(self: *DomParser, mnode: *MutableNode, parent: NodeIndex) !NodeIndex {
        const tag = switch (mnode.kind) {
            .element => mnode.u.element.tag,
            .processing_instruction => mnode.u.processing_instruction.target,
            else => null,
        };
        const content = switch (mnode.kind) {
            .text => mnode.u.text.content,
            .cdata => mnode.u.cdata.content,
            .comment => mnode.u.comment.content,
            .processing_instruction => mnode.u.processing_instruction.content,
            else => null,
        };
        const idx = try self.dom.addNode(mnode.kind, tag, content, parent);
        const attr_start: u32 = @intCast(self.dom.attributes.items.len);
        const attrs = switch (mnode.kind) {
            .element => mnode.u.element.attributes.items,
            else => &[_]Attribute{},
        };
        try self.dom.attributes.appendSlice(attrs);
        self.dom.nodes.items[idx].attributes_range = .{ .start = attr_start, .len = @intCast(attrs.len) };
        var child_indices = std.ArrayList(NodeIndex).init(self.allocator);
        defer child_indices.deinit();
        const children = switch (mnode.kind) {
            .element => mnode.u.element.children.items,
            else => &[_]*MutableNode{},
        };
        for (children) |child| {
            const child_idx = try self.freeze(child, idx);
            try child_indices.append(child_idx);
        }
        const child_start: u32 = @intCast(self.dom.children.items.len);
        try self.dom.children.appendSlice(child_indices.items);
        self.dom.nodes.items[idx].children_range = .{ .start = child_start, .len = @intCast(child_indices.items.len) };
        return idx;
    }
};

pub fn handlerCallback(context: ?*anyopaque, entity: Entity) callconv(.C) void {
    const self: *DomParser = @ptrCast(@alignCast(context));
    self.handleEvent(entity) catch |err| {
        self.parse_error = err;
    };
}

pub fn parseDom(dom: *DOM, xml: []const u8, allocator: Allocator) !Document {
    var parser = DomParser.init(allocator, dom);
    defer parser.deinit();
    var sp = try SaxParser.init(allocator, &parser, handlerCallback);
    defer sp.deinit();
    try sp.write(xml);
    if (parser.parse_error) |err| return err;
    return try parser.build();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator: Allocator = gpa.allocator();

    var dom = DOM.init(allocator);
    defer dom.deinit();

    const tag_root = try dom.interner.intern("html");
    const tag_body = try dom.interner.intern("body");
    _ = try dom.interner.intern("Hello");

    const doc1 = try dom.createDocument(.element, tag_root);
    const body_node = try dom.addNode(.element, tag_body, null, doc1.root);

    var batch = TransformBatch.init(allocator);
    defer batch.deinit();

    try batch.replaceChildren(doc1.root, &[_]NodeIndex{ body_node });

    const attr_class = try dom.interner.intern("class");
    const attr_val = try dom.interner.intern("main");
    try batch.setAttributes(body_node, &[_]Attribute{.{ .name_id = attr_class, .value_id = attr_val }});

    const doc2 = try dom.applyBatch(doc1, &batch);

    std.debug.print("Generation after batch: {}\n", .{ doc2.generation });
}

const testing = std.testing;

test "parse simple xml" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dom = DOM.init(allocator);
    defer dom.deinit();

    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?><root id="1"><child class="test">Hello, <b>World</b>!</child></root>
    ;

    const doc = try parseDom(&dom, xml, allocator);

    // Verify root
    const root = dom.nodes.items[doc.root];
    try testing.expectEqual(NodeKind.element, root.kind);
    const root_tag = dom.interner.get(root.tag.?);
    try testing.expectEqualStrings("root", root_tag);

    // Root attributes
    const root_attrs = dom.attributes.items[root.attributes_range.start..root.attributes_range.start + root.attributes_range.len];
    try testing.expectEqual(@as(u32, 1), root.attributes_range.len);
    try testing.expectEqualStrings("id", dom.interner.get(root_attrs[0].name_id));
    try testing.expectEqualStrings("1", dom.interner.get(root_attrs[0].value_id));

    try testing.expectEqual(@as(u32, 1), root.children_range.len);

    const child_idx = dom.children.items[root.children_range.start];
    const child = dom.nodes.items[child_idx];
    try testing.expectEqual(NodeKind.element, child.kind);
    const child_tag = dom.interner.get(child.tag.?);
    try testing.expectEqualStrings("child", child_tag);

    // Child attributes
    const child_attrs = dom.attributes.items[child.attributes_range.start..child.attributes_range.start + child.attributes_range.len];
    try testing.expectEqual(@as(u32, 1), child.attributes_range.len);
    try testing.expectEqualStrings("class", dom.interner.get(child_attrs[0].name_id));
    try testing.expectEqualStrings("test", dom.interner.get(child_attrs[0].value_id));

    try testing.expectEqual(@as(u32, 3), child.children_range.len);

    // First text: "Hello, "
    const text1_idx = dom.children.items[child.children_range.start];
    const text1 = dom.nodes.items[text1_idx];
    try testing.expectEqual(NodeKind.text, text1.kind);
    try testing.expect(text1.tag == null);
    try testing.expectEqualStrings("Hello, ", dom.interner.get(text1.content.?));
    try testing.expectEqual(@as(u32, 0), text1.attributes_range.len);
    try testing.expectEqual(@as(u32, 0), text1.children_range.len);

    // Element b
    const b_idx = dom.children.items[child.children_range.start + 1];
    const b = dom.nodes.items[b_idx];
    try testing.expectEqual(NodeKind.element, b.kind);
    const b_tag = dom.interner.get(b.tag.?);
    try testing.expectEqualStrings("b", b_tag);
    try testing.expectEqual(@as(u32, 0), b.attributes_range.len);
    try testing.expectEqual(@as(u32, 1), b.children_range.len);

    // b's text: "World"
    const b_text_idx = dom.children.items[b.children_range.start];
    const b_text = dom.nodes.items[b_text_idx];
    try testing.expectEqual(NodeKind.text, b_text.kind);
    try testing.expect(b_text.tag == null);
    try testing.expectEqualStrings("World", dom.interner.get(b_text.content.?));
    try testing.expectEqual(@as(u32, 0), b_text.attributes_range.len);
    try testing.expectEqual(@as(u32, 0), b_text.children_range.len);

    // Second text: "!"
    const text2_idx = dom.children.items[child.children_range.start + 2];
    const text2 = dom.nodes.items[text2_idx];
    try testing.expectEqual(NodeKind.text, text2.kind);
    try testing.expect(text2.tag == null);
    try testing.expectEqualStrings("!", dom.interner.get(text2.content.?));
    try testing.expectEqual(@as(u32, 0), text2.attributes_range.len);
    try testing.expectEqual(@as(u32, 0), text2.children_range.len);
}
