const std = @import("std");

const Allocator = std.mem.Allocator;

const NodeIndex = u32;
const StringId = u32;
const InvalidIndex: NodeIndex = 0xffffffff;
const InvalidString: StringId = 0xffffffff;

const Range = struct {
    start: u32,
    len: u32,
};

const NodeKind = enum {
    element,
    text,
};

const Attribute = struct {
    name_id: StringId,
    value_id: StringId,
};

const Node = struct {
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
    nodes: std.ArrayList(Node),
    children: std.ArrayList(NodeIndex),
    attributes: std.ArrayList(Attribute),

    pub fn init(allocator: Allocator) DOM {
        return DOM{
            .allocator = allocator,
            .interner = StringInterner.init(allocator),
            .nodes = std.ArrayList(Node).init(allocator),
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

    pub fn setAttributes(self: *DOM, doc: Document, node: NodeIndex, attrs: []const Attribute) !Document {
        const new_start: u32 = @intCast(self.attributes.items.len);
        try self.attributes.appendSlice(attrs);

        var new_node = self.nodes.items[node];
        new_node.attributes_range = .{ .start = new_start, .len = @intCast(attrs.len) };
        // const new_idx: NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(new_node);

        return .{
            .root = doc.root,
            .nodes_len = @intCast(self.nodes.items.len),
            .children_len = doc.children_len,
            .attributes_len = @intCast(self.attributes.items.len),
            .generation = doc.generation + 1,
        };
    }

    pub fn replaceChildren(
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
        // var preorder_counter = start;
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator: Allocator = gpa.allocator();

    var dom = DOM.init(allocator);
    defer dom.deinit();

    const tag_root = try dom.interner.intern("html");
    const tag_body = try dom.interner.intern("body");
    _ = try dom.interner.intern("Hello");

    var doc1 = try dom.createDocument(.element, tag_root);

    const body_node = try dom.addNode(.element, tag_body, doc1.root);
    doc1 = try dom.replaceChildren(doc1, doc1.root, &[_]NodeIndex{ body_node });

    const text_node = try dom.addNode(.text, null, body_node);
    doc1 = try dom.replaceChildren(doc1, body_node, &[_]NodeIndex{ text_node });

    // Set attributes on <body>
    const attr_class = try dom.interner.intern("class");
    const attr_val = try dom.interner.intern("main");
    const doc2 = try dom.setAttributes(doc1, body_node, &[_]Attribute{
        .{ .name_id = attr_class, .value_id = attr_val },
    });

    std.debug.print("Root tag: {s}\n", .{ dom.interner.get(dom.nodes.items[doc2.root].tag.?) });
    std.debug.print("Body attrs: {}\n", .{ dom.nodes.items[body_node].attributes_range.len });
    std.debug.print("root attrs: {}\n", .{ dom.attributes.items.len });
}


// TODO
// If you want, I can next implement a Transformation struct that batches replaceChildren, setAttributes, and setText into a single pass over the tree so we only COW the path to the root once. That will give you true batched transformations.
// Do you want me to add that batching layer next?
