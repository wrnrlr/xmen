// XML DOM implementation
const std = @import("std");

const Allocator = std.mem.Allocator;
const NodeIndex = u32;
const StringId = u32;
const InvalidIndex: NodeIndex = 0xffffffff;
const InvalidString: StringId = 0xffffffff;

const Range = struct { start: u32, len: u32 };
const NodeKind = enum { element, text };

const Attribute = struct {
    name_id: StringId,
    value_id: StringId,
};

const Element = struct {
    kind: NodeKind,
    tag: ?StringId,
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

    pub fn addNode(self: *DOM, kind: NodeKind, tag: ?StringId, parent: NodeIndex) !NodeIndex {
        const idx: NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(.{
            .kind = kind,
            .tag = tag,
            .attributes_range = .{ .start = 0, .len = 0 },
            .children_range = .{ .start = 0, .len = 0 },
            .parent = parent,
            .preorder = 0,
            .subtree_size = 1,
        });
        return idx;
    }

    pub fn createDocument(self: *DOM, root_kind: NodeKind, root_tag: ?StringId) !Document {
        const root_idx = try self.addNode(root_kind, root_tag, InvalidIndex);
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

        while (stack.items.len > 0) {
            const idx = stack.pop() orelse unreachable;
            var node = &self.nodes.items[idx];
            node.preorder = next_preorder;
            next_preorder += 1;

            var child_count: u32 = 0;
            const cr = node.children_range;
            for (self.children.items[cr.start .. cr.start + cr.len]) |c| {
                try stack.append(c);
                child_count += 1;
            }
            node.subtree_size = child_count + 1;
        }
        return next_preorder;
    }
};

const sax = @import("sax.zig");
const SaxParser = sax.SaxParser;
const Entity = sax.Entity;

const MutableNode = struct {
    kind: NodeKind,
    tag: ?StringId,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(*MutableNode),

    pub fn init(allocator: Allocator, kind: NodeKind, tag: ?StringId) MutableNode {
        return .{
            .kind = kind,
            .tag = tag,
            .attributes = std.ArrayList(Attribute).init(allocator),
            .children = std.ArrayList(*MutableNode).init(allocator),
        };
    }

    pub fn deinit(self: *MutableNode) void {
        for (self.children.items) |child| {
            child.deinit();
            self.children.allocator.destroy(child);
        }
        self.children.deinit();
        self.attributes.deinit();
    }
};

const DomParser = struct {
    allocator: Allocator,
    dom: *DOM,
    stack: std.ArrayList(*MutableNode),
    root: ?*MutableNode = null,

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
            r.deinit();
            self.allocator.destroy(r);
        }
    }

    pub fn handleEvent(self: *DomParser, entity: Entity) !void {
        switch (entity.tag) {
            .open_tag => {
                const tag_data = entity.data.open_tag;
                const tag_str = tag_data.name[0..tag_data.name_len];
                const tag_id = try self.dom.interner.intern(tag_str);

                const node = try self.allocator.create(MutableNode);
                errdefer self.allocator.destroy(node);
                node.* = MutableNode.init(self.allocator, .element, tag_id);

                for (0..tag_data.attributes_len) |i| {
                    const attr = tag_data.attributes[i];
                    const name_str = attr.name[0..attr.name_len];
                    const value_str = attr.value[0..attr.value_len];
                    const name_id = try self.dom.interner.intern(name_str);
                    const value_id = try self.dom.interner.intern(value_str);
                    try node.attributes.append(.{ .name_id = name_id, .value_id = value_id });
                }

                if (self.root == null) {
                    self.root = node;
                } else if (self.stack.items.len > 0) {
                    try self.stack.items[self.stack.items.len - 1].children.append(node);
                } else {
                    return error.MultipleRoots;
                }
                try self.stack.append(node);
            },
            .close_tag => {
                _ = self.stack.pop();
            },
            .text, .cdata => {
                const text_data = if (entity.tag == .text) entity.data.text else entity.data.cdata;
                const text_str = text_data.value[0..(text_data.header[1] - text_data.header[0])];
                if (text_str.len == 0) return;
                if (self.stack.items.len == 0) return; // Ignore top-level text

                const text_id = try self.dom.interner.intern(text_str);
                const node = try self.allocator.create(MutableNode);
                errdefer self.allocator.destroy(node);
                node.* = MutableNode.init(self.allocator, .text, text_id);

                try self.stack.items[self.stack.items.len - 1].children.append(node);
            },
            else => {}, // Ignore comments, processing instructions, etc.
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
        const idx = try self.dom.addNode(mnode.kind, mnode.tag, parent);
        const attr_start: u32 = @intCast(self.dom.attributes.items.len);
        try self.dom.attributes.appendSlice(mnode.attributes.items);
        self.dom.nodes.items[idx].attributes_range = .{ .start = attr_start, .len = @intCast(mnode.attributes.items.len) };
        const child_start: u32 = @intCast(self.dom.children.items.len);
        for (mnode.children.items) |child| {
            const child_idx = try self.freeze(child, idx);
            try self.dom.children.append(child_idx);
        }
        self.dom.nodes.items[idx].children_range = .{ .start = child_start, .len = @intCast(mnode.children.items.len) };
        return idx;
    }
};

pub fn handlerCallback(context: ?*anyopaque, entity: Entity) callconv(.C) void {
    const self: *DomParser = @ptrCast(@alignCast(context));
    self.handleEvent(entity) catch {};
}

pub fn parseDom(dom: *DOM, xml: []const u8, allocator: Allocator) !Document {
    var parser = DomParser.init(allocator, dom);
    defer parser.deinit();
    var sp = try SaxParser.init(allocator, &parser, handlerCallback);
    defer sp.deinit();
    try sp.write(xml);
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
    const body_node = try dom.addNode(.element, tag_body, doc1.root);

    var batch = TransformBatch.init(allocator);
    defer batch.deinit();

    try batch.replaceChildren(doc1.root, &[_]NodeIndex{ body_node });

    const attr_class = try dom.interner.intern("class");
    const attr_val = try dom.interner.intern("main");
    try batch.setAttributes(body_node, &[_]Attribute{.{ .name_id = attr_class, .value_id = attr_val }});

    const doc2 = try dom.applyBatch(doc1, &batch);

    std.debug.print("Generation after batch: {}\n", .{ doc2.generation });
}

// TODO
// If you want, I can next implement a Transformation struct that batches replaceChildren, setAttributes, and setText into a single pass over the tree so we only COW the path to the root once. That will give you true batched transformations.
// Do you want me to add that batching layer next?

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

    std.debug.print("children range {d}\n", .{root.children_range.len});
    try testing.expectEqual(1, root.children_range.len);

    const child_idx = dom.children.items[root.children_range.start];
    const child = dom.nodes.items[child_idx];

    const b_idx = dom.children.items[child.children_range.start];
    const b = dom.nodes.items[b_idx];
    try testing.expectEqual(NodeKind.element, b.kind);
    const b_tag = dom.interner.get(b.tag.?);
    try testing.expectEqualStrings("b", b_tag);
    try testing.expectEqual(@as(u32, 0), b.attributes_range.len);
}
