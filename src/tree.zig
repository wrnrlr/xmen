const std = @import("std");

const Allocator = std.mem.Allocator;

const NodeIndex = u32;
const InvalidIndex: NodeIndex = 0xffffffff;

const Range = struct {
    start: u32,
    len: u32,
};

const NodeKind = enum {
    element,
    text,
};

const Node = struct {
    kind: NodeKind,
    tag: ?u32,            // interned tag id for elements
    children_range: Range,
    parent: NodeIndex,    // optional, InvalidIndex if root
};

const Document = struct {
    root: NodeIndex,
    nodes_len: u32,
    children_len: u32,
    generation: u64,
};

const DOM = struct {
    allocator: Allocator,
    nodes: std.ArrayList(Node),
    children: std.ArrayList(NodeIndex),

    pub fn init(allocator: Allocator) DOM {
        return DOM{
            .allocator = allocator,
            .nodes = std.ArrayList(Node).init(allocator),
            .children = std.ArrayList(NodeIndex).init(allocator),
        };
    }

    pub fn deinit(self: *DOM) void {
        self.nodes.deinit();
        self.children.deinit();
    }

    /// Adds a new node and returns its index
    pub fn addNode(self: *DOM, kind: NodeKind, tag: ?u32, parent: NodeIndex) !NodeIndex {
        const idx:NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(Node{
            .kind = kind,
            .tag = tag,
            .children_range = Range{ .start = 0, .len = 0 },
            .parent = parent,
        });
        return idx;
    }

    /// Create an initial document with a single root element
    pub fn createDocument(self: *DOM, root_kind: NodeKind, root_tag: ?u32) !Document {
        const root_idx = try self.addNode(root_kind, root_tag, InvalidIndex);
        return Document{
            .root = root_idx,
            .nodes_len = 1,
            .children_len = 0,
            .generation = 1,
        };
    }

    /// Replace the children of a node in a given document (copy-on-write)
    pub fn replaceChildren(
        self: *DOM,
        doc: Document,
        parent: NodeIndex,
        new_children: []const NodeIndex,
    ) !Document {
        // allocate new children slice
        const new_start:u32 = @intCast(self.children.items.len);
        try self.children.appendSlice(new_children);

        // copy parent node with updated children_range
        const old_parent = self.nodes.items[parent];
        var new_parent = old_parent;
        new_parent.children_range = Range{ .start = new_start, .len = @intCast(new_children.len) };
        const new_parent_idx:NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(new_parent);

        // propagate copies up to root
        var cur = parent;
        var new_child_idx = new_parent_idx;
        while (true) {
            const p = self.nodes.items[cur].parent;
            if (p == InvalidIndex) break;

            const pnode = self.nodes.items[p];
            const slice_start = pnode.children_range.start;
            const slice_len = pnode.children_range.len;

            const new_slice_start:u32 = @intCast(self.children.items.len);
            for (self.children.items[slice_start .. slice_start + slice_len]) |child| {
                if (child == cur) {
                    try self.children.append(new_child_idx);
                } else {
                    try self.children.append(child);
                }
            }

            var new_pnode = pnode;
            new_pnode.children_range = Range{ .start = new_slice_start, .len = slice_len };
            const new_p_idx:NodeIndex = @intCast(self.nodes.items.len);
            try self.nodes.append(new_pnode);

            new_child_idx = new_p_idx;
            cur = p;
        }

        return Document{
            .root = new_child_idx,
            .nodes_len = @intCast(self.nodes.items.len),
            .children_len = @intCast(self.children.items.len),
            .generation = doc.generation + 1,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator:std.mem.Allocator = gpa.allocator();

    var dom = DOM.init(allocator);
    defer dom.deinit();

    // Create base doc
    var doc1 = try dom.createDocument(.element, 1); // tag=1 for example

    // Add a child to root
    const child1 = try dom.addNode(.element, 2, doc1.root);
    doc1 = try dom.replaceChildren(doc1, doc1.root, &[_]NodeIndex{ child1 });

    // Add another child (copy-on-write)
    const child2 = try dom.addNode(.text, null, doc1.root);
    const doc2 = try dom.replaceChildren(doc1, doc1.root, &[_]NodeIndex{ child1, child2 });

    std.debug.print("doc1 root children_len={}\n", .{ dom.nodes.items[doc1.root].children_range.len });
    std.debug.print("doc2 root children_len={}\n", .{ dom.nodes.items[doc2.root].children_range.len });
}
