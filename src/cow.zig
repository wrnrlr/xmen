const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

// String interning for efficient string storage
const StringPool = struct {
    strings: ArrayList([]const u8),
    map: std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .strings = ArrayList([]const u8).init(allocator),
            .map = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.strings.items) |str|
            self.strings.allocator.free(str);
        self.strings.deinit();
        self.map.deinit();
    }

    pub fn intern(self: *Self, str: []const u8) !u32 {
        if (self.map.get(str)) |id|
            return id;
        const owned_str = try self.strings.allocator.dupe(u8, str);
        const id: u32 = @intCast(self.strings.items.len);
        try self.strings.append(owned_str);
        try self.map.put(owned_str, id);
        return id;
    }

    pub fn getString(self: *const Self, id: u32) []const u8 {
        return self.strings.items[id];
    }
};

// Node types
pub const NodeType = enum(u8) {
    element = 1,
    attribute = 2,
    text = 3,
    cdata = 4,
    proc_inst = 7,
    comment = 8,
    document = 9,
};

const TextData = struct {
    content: u32,
    parent: u32 = 0,
    next: u32 = 0,
};

// NodeData as a tagged union to optimize storage
const NodeData = union(NodeType) {
    element: struct {
        tag_name: u32,
        parent: u32 = 0,
        first_child: u32 = 0,
        last_child: u32 = 0,
        next: u32 = 0,
        first_attr: u32 = 0,
        last_attr: u32 = 0,
    },
    attribute: struct {
        name: u32,
        value: u32,
        parent: u32 = 0,
        next: u32 = 0,
    },
    text: TextData,
    cdata: TextData,
    proc_inst: TextData,
    comment: TextData,
    document: struct {
        first_child: u32 = 0,
        last_child: u32 = 0,
    },
};

// Transformation actions for copy-on-write operations
const ActionType = enum {
    CreateDocument,
    CreateElement,
    CreateAttribute,
    CreateText,
    CreateCDATA,
    CreateProcessingInstruction,
    CreateComment,
    AppendChild,
    PrependChild,
    RemoveChild,
    SetAttribute,
    RemoveAttribute,
};

const Action = union(ActionType) {
    CreateDocument: CreateDocumentAction,
    CreateElement: CreateElementAction,
    CreateAttribute: CreateAttributeAction,
    CreateText: CreateTextAction,
    CreateCDATA: CreateCDATASectionAction,
    CreateProcessingInstruction: CreateProcessingInstructionAction,
    CreateComment: CreateCommentAction,
    AppendChild: AppendChildAction,
    PrependChild: PrependChildAction,
    RemoveChild: RemoveChildAction,
    SetAttribute: SetAttributeAction,
    RemoveAttribute: RemoveAttributeAction,

    fn apply(self: Action, dom: *DOM) !void {
      switch (self) {
          .CreateDocument => |a| try a.apply(dom),
          .CreateElement => |a| try a.apply(dom),
          .CreateAttribute => |a| try a.apply(dom),
          .CreateText => |a| try a.apply(dom),
          .CreateCDATA => |a| try a.apply(dom),
          .CreateProcessingInstruction => |a| try a.apply(dom),
          .CreateComment => |a| try a.apply(dom),
          .AppendChild => |a| try a.apply(dom),
          .PrependChild => |a| try a.apply(dom),
          .RemoveChild => |a| try a.apply(dom),
          .SetAttribute => |a| try a.apply(dom),
          .RemoveAttribute => |a| try a.apply(dom),
      }
    }
};

const CreateDocumentAction = struct {
    node_id: u32,

    pub fn apply(self: CreateDocumentAction, dom: *DOM) !void {
        const node_data = NodeData{ .document = .{} };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateElementAction = struct {
    node_id: u32,
    tag_name: u32,

    pub fn apply(self: CreateElementAction, dom: *DOM) !void {
        const node_data = NodeData{ .element = .{ .tag_name = self.tag_name } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateAttributeAction = struct {
    node_id: u32,
    name: u32,
    value: u32,

    pub fn apply(self: CreateAttributeAction, dom: *DOM) !void {
        const node_data = NodeData{ .attribute = .{ .name = self.name, .value = self.value } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateTextAction = struct {
    node_id: u32,
    content: u32,

    pub fn apply(self: CreateTextAction, dom: *DOM) !void {
        const node_data = NodeData{ .text = .{ .content = self.content } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateCDATASectionAction = struct {
    node_id: u32,
    content: u32,

    pub fn apply(self: CreateCDATASectionAction, dom: *DOM) !void {
        const node_data = NodeData{ .cdata = .{ .content = self.content } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateProcessingInstructionAction = struct {
    node_id: u32,
    target: u32,
    content: u32,

    pub fn apply(self: CreateProcessingInstructionAction, dom: *DOM) !void {
        const node_data = NodeData{ .proc_inst = .{ .content = self.content } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const CreateCommentAction = struct {
    node_id: u32,
    content: u32,

    pub fn apply(self: CreateCommentAction, dom: *DOM) !void {
        const node_data = NodeData{ .comment = .{ .content = self.content } };
        try dom.createNodeAt(self.node_id, node_data);
    }
};

const AppendChildAction = struct {
    parent: u32,
    child: u32,

    pub fn apply(self: AppendChildAction, dom: *DOM) !void {
        if (self.parent == 0 or self.child == 0 or self.parent > dom.nodes.items.len or self.child > dom.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_data = dom.getNodeData(self.parent - 1);
        const child_data = dom.getNodeData(self.child - 1);

        // Set child parent and next = 0
        switch (child_data.*) {
            .element => |*e| {
                e.parent = self.parent;
                e.next = 0;
            },
            .text => |*t| {
                t.parent = self.parent;
                t.next = 0;
            },
            .cdata => |*c| {
                c.parent = self.parent;
                c.next = 0;
            },
            .proc_inst => |*p| {
                p.parent = self.parent;
                p.next = 0;
            },
            .comment => |*co| {
                co.parent = self.parent;
                co.next = 0;
            },
            else => return error.InvalidChildType,
        }

        // Get first_child
        const first_child = switch (parent_data.*) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => return error.InvalidParentType,
        };

        if (first_child == 0) {
            switch (parent_data.*) {
                .document => |*d| {
                    d.first_child = self.child;
                    d.last_child = self.child;
                },
                .element => |*e| {
                    e.first_child = self.child;
                    e.last_child = self.child;
                },
                else => unreachable,
            }
        } else {
            const last_child = switch (parent_data.*) {
                .document => |d| d.last_child,
                .element => |e| e.last_child,
                else => unreachable,
            };
            const last_data = &dom.nodes.items[last_child - 1];
            switch (last_data.*) {
                .element => |*e| e.next = self.child,
                .text => |*t| t.next = self.child,
                .cdata => |*c| c.next = self.child,
                .proc_inst => |*p| p.next = self.child,
                .comment => |*co| co.next = self.child,
                else => return error.InvalidChildType,
            }
            switch (parent_data.*) {
                .document => |*d| d.last_child = self.child,
                .element => |*e| e.last_child = self.child,
                else => unreachable,
            }
        }
    }
};

const PrependChildAction = struct {
    parent: u32,
    child: u32,

    pub fn apply(self: PrependChildAction, dom: *DOM) !void {
        if (self.parent == 0 or self.child == 0 or self.parent > dom.nodes.items.len or self.child > dom.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_data = dom.getNodeData(self.parent - 1);
        const child_data = dom.getNodeData(self.child - 1);

        // Set child parent
        switch (child_data.*) {
            .element => |*e| e.parent = self.parent,
            .text => |*t| t.parent = self.parent,
            .cdata => |*c| c.parent = self.parent,
            .proc_inst => |*p| p.parent = self.parent,
            .comment => |*co| co.parent = self.parent,
            else => return error.InvalidChildType,
        }

        const old_first = switch (parent_data.*) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => return error.InvalidParentType,
        };

        // Set child next to old_first
        switch (child_data.*) {
            .element => |*e| e.next = old_first,
            .text => |*t| t.next = old_first,
            .cdata => |*c| c.next = old_first,
            .proc_inst => |*p| p.next = old_first,
            .comment => |*co| co.next = old_first,
            else => unreachable,
        }

        // Set parent first_child to child_id
        switch (parent_data.*) {
            .document => |*d| d.first_child = self.child,
            .element => |*e| e.first_child = self.child,
            else => unreachable,
        }

        if (switch (parent_data.*) {
            .document => |d| d.last_child,
            .element => |e| e.last_child,
            else => unreachable,
        } == 0) {
            switch (parent_data.*) {
                .document => |*d| d.last_child = self.child,
                .element => |*e| e.last_child = self.child,
                else => unreachable,
            }
        }
    }
};

const RemoveChildAction = struct {
    parent: u32,
    child: u32,

    pub fn apply(self: RemoveChildAction, dom: *DOM) !void {
        if (self.parent == 0 or self.child == 0 or self.parent > dom.nodes.items.len or self.child > dom.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_data = dom.getNodeData(self.parent - 1);

        var current = switch (parent_data.*) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => return error.InvalidParentType,
        };
        var prev: u32 = 0;
        while (current != 0) {
            if (current == self.child) {
                const current_idx = current - 1;
                const current_data = &dom.nodes.items[current_idx];
                const next = dom.getNext(current_idx);

                if (prev == 0) {
                    switch (parent_data.*) {
                        .document => |*d| d.first_child = next,
                        .element => |*e| e.first_child = next,
                        else => unreachable,
                    }
                } else {
                    const prev_data = &dom.nodes.items[prev - 1];
                    switch (prev_data.*) {
                        .element => |*e| e.next = next,
                        .text => |*t| t.next = next,
                        .cdata => |*c| c.next = next,
                        .proc_inst => |*p| p.next = next,
                        .comment => |*co| co.next = next,
                        else => unreachable,
                    }
                }

                if (switch (parent_data.*) {
                    .document => |d| d.last_child,
                    .element => |e| e.last_child,
                    else => unreachable,
                } == self.child) {
                    switch (parent_data.*) {
                        .document => |*d| d.last_child = prev,
                        .element => |*e| e.last_child = prev,
                        else => unreachable,
                    }
                }

                switch (current_data.*) {
                    .element => |*e| {
                        e.parent = 0;
                        e.next = 0;
                    },
                    .text => |*t| {
                        t.parent = 0;
                        t.next = 0;
                    },
                    .cdata => |*c| {
                        c.parent = 0;
                        c.next = 0;
                    },
                    .proc_inst => |*p| {
                        p.parent = 0;
                        p.next = 0;
                    },
                    .comment => |*co| {
                        co.parent = 0;
                        co.next = 0;
                    },
                    else => unreachable,
                }
                return;
            }

            prev = current;
            current = dom.getNext(current - 1);
        }

        return error.ChildNotFound;
    }
};

const SetAttributeAction = struct {
    element: u32,
    name: u32,
    value: u32,

    pub fn apply(self: SetAttributeAction, dom: *DOM) !void {
        if (self.element == 0 or self.element > dom.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const element_data = dom.getNodeData(self.element - 1);

        const first_attr = switch (element_data.*) {
            .element => |e| e.first_attr,
            else => return error.NotElement,
        };

        // Check if attribute exists
        var current = first_attr;
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_data = dom.getNodeData(attr_idx);
            const name = switch (attr_data.*) {
                .attribute => |a| a.name,
                else => return error.InvalidAttributeType,
            };
            if (name == self.name) {
                switch (attr_data.*) {
                    .attribute => |*a| a.value = self.value,
                    else => unreachable,
                }
                return;
            }
            prev = current;
            current = dom.getNext(attr_idx);
        }

        // Create new attribute node
        const new_id: u32 = @intCast(dom.nodes.items.len + 1);
        const attr_data = NodeData{ .attribute = .{ .name = self.name, .value = self.value, .parent = self.element } };
        try dom.createNodeAt(new_id, attr_data);

        // Append to attribute list
        switch (element_data.*) {
            .element => |*e| {
                if (e.first_attr == 0) {
                    e.first_attr = new_id;
                    e.last_attr = new_id;
                } else {
                    const last_idx = e.last_attr - 1;
                    const last_attr_data = &dom.nodes.items[last_idx];
                    switch (last_attr_data.*) {
                        .attribute => |*a| a.next = new_id,
                        else => unreachable,
                    }
                    e.last_attr = new_id;
                }
            },
            else => unreachable,
        }
    }
};

const RemoveAttributeAction = struct {
    element: u32,
    name: u32,

    pub fn apply(self: RemoveAttributeAction, dom: *DOM) !void {
        if (self.element == 0 or self.element > dom.nodes.items.len)
            return error.InvalidNodeIndex;

        const element_idx = self.element - 1;
        const element_data = &dom.nodes.items[element_idx];

        var current = switch (element_data.*) {
            .element => |e| e.first_attr,
            else => return error.NotElement,
        };
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_data = &dom.nodes.items[attr_idx];
            const name = switch (attr_data.*) {
                .attribute => |a| a.name,
                else => return error.InvalidAttributeType,
            };
            if (name == self.name) {
                const next = switch (attr_data.*) {
                    .attribute => |a| a.next,
                    else => unreachable,
                };

                if (prev == 0) {
                    switch (element_data.*) {
                        .element => |*e| e.first_attr = next,
                        else => unreachable,
                    }
                } else {
                    const prev_data = &dom.nodes.items[prev - 1];
                    switch (prev_data.*) {
                        .attribute => |*a| a.next = next,
                        else => unreachable,
                    }
                }

                if (switch (element_data.*) {
                    .element => |e| e.last_attr,
                    else => unreachable,
                } == current) {
                    switch (element_data.*) {
                        .element => |*e| e.last_attr = prev,
                        else => unreachable,
                    }
                }

                switch (attr_data.*) {
                    .attribute => |*a| {
                        a.parent = 0;
                        a.next = 0;
                    },
                    else => unreachable,
                }
                return;
            }
            prev = current;
            current = switch (attr_data.*) {
                .attribute => |a| a.next,
                else => unreachable,
            };
        }

        // Attribute not found, do nothing
    }
};

// Builder for creating actions separately from DOM, maintaining immutability
const Builder = struct {
    strings: StringPool,
    next_node_id: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Builder {
        var res = Builder{
            .allocator = allocator,
            .strings = StringPool.init(allocator),
            .next_node_id = 1, // 0 is reserved
        };
        const empty = try allocator.dupe(u8, "");
        try res.strings.strings.append(empty);
        return res;
    }

    pub fn deinit(self: *Builder) void {
        self.strings.deinit();
    }
};

// Helper functions for creating actions using Builder
pub fn createDocumentAction(builder: *Builder) !struct { action: Action, node_id: u32 } {
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateDocument = .{ .node_id = node_id } },
        .node_id = node_id,
    };
}

pub fn createElementAction(builder: *Builder, tag_name: []const u8) !struct { action: Action, node_id: u32 } {
    const tag_id = try builder.strings.intern(tag_name);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateElement = .{ .node_id = node_id, .tag_name = tag_id } },
        .node_id = node_id,
    };
}

pub fn createAttributeAction(builder: *Builder, name: []const u8, value: []const u8) !struct { action: Action, node_id: u32 } {
    const name_id = try builder.strings.intern(name);
    const value_id = try builder.strings.intern(value);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateAttribute = .{ .node_id = node_id, .name = name_id, .value = value_id } },
        .node_id = node_id,
    };
}

pub fn createTextAction(builder: *Builder, text: []const u8) !struct { action: Action, node_id: u32 } {
    const text_id = try builder.strings.intern(text);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateText = .{ .node_id = node_id, .content = text_id } },
        .node_id = node_id,
    };
}

pub fn createCDATASectionAction(builder: *Builder, data: []const u8) !struct { action: Action, node_id: u32 } {
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateCDATA = .{ .node_id = node_id, .content = data_id } },
        .node_id = node_id,
    };
}

pub fn createProcessingInstructionAction(builder: *Builder, target: []const u8, data: []const u8) !struct { action: Action, node_id: u32 } {
    const target_id = try builder.strings.intern(target);
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateProcessingInstruction = .{ .node_id = node_id, .target = target_id, .content = data_id } },
        .node_id = node_id,
    };
}

pub fn createCommentAction(builder: *Builder, data: []const u8) !struct { action: Action, node_id: u32 } {
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = .{ .CreateComment = .{ .node_id = node_id, .content = data_id } },
        .node_id = node_id,
    };
}

pub fn appendChildAction(parent_id: u32, child_id: u32) Action {
    return .{ .AppendChild = .{ .parent = parent_id, .child = child_id } };
}

pub fn prependChildAction(parent_id: u32, child_id: u32) Action {
    return .{ .PrependChild = .{ .parent = parent_id, .child = child_id } };
}

pub fn removeChildAction(parent_id: u32, child_id: u32) Action {
    return .{ .RemoveChild = .{ .parent = parent_id, .child = child_id } };
}

pub fn setAttributeAction(builder: *Builder, element_id: u32, name: []const u8, value: []const u8) !Action {
    const name_id = try builder.strings.intern(name);
    const value_id = try builder.strings.intern(value);

    return .{ .SetAttribute = .{ .element = element_id, .name = name_id, .value = value_id } };
}

pub fn removeAttributeAction(builder: *Builder, element_id: u32, name: []const u8) !Action {
    const name_id = try builder.strings.intern(name);

    return .{ .RemoveAttribute = .{ .element = element_id, .name = name_id } };
}

// Main DOM World - copy-on-write container
const DOM = struct {
    // Core data
    nodes: ArrayList(NodeData),
    strings: StringPool,

    // Transformation tracking
    version: u32,
    actions: ArrayList(Action),

    pub fn init(allocator: Allocator) !DOM {
        var res = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
            .version = 0,
            .actions = ArrayList(Action).init(allocator),
        };
        const empty = try allocator.dupe(u8, "");
        try res.strings.strings.append(empty);
        return res;
    }

    pub fn deinit(self: *DOM) void {
        self.nodes.deinit();
        self.strings.deinit();
        self.actions.deinit();
    }

    pub fn createBuilder(self: *const DOM, allocator: Allocator) !Builder {
        var builder = Builder{
            .allocator = allocator,
            .strings = StringPool.init(allocator),
            .next_node_id = @intCast(self.nodes.items.len + 1),
        };

        // Copy strings
        for (self.strings.strings.items) |str| {
            const dup = try allocator.dupe(u8, str);
            try builder.strings.strings.append(dup);
        }

        var it = self.strings.map.iterator();
        while (it.next()) |entry| {
            const new_str = builder.strings.strings.items[entry.value_ptr.*];
            try builder.strings.map.put(new_str, entry.value_ptr.*);
        }

        return builder;
    }

    // Create a new world by applying transformations (copy-on-write)
    pub fn transform(self: *const DOM, builder: *const Builder, actions: []const Action, allocator: Allocator) !DOM {
        var dom = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
            .version = self.version + 1,
            .actions = ArrayList(Action).init(allocator),
        };

        // Copy existing nodes
        try dom.nodes.appendSlice(self.nodes.items);

        // Copy builder's strings (which include original + new)
        for (builder.strings.strings.items) |str| {
            const dup = try allocator.dupe(u8, str);
            try dom.strings.strings.append(dup);
        }

        var it = builder.strings.map.iterator();
        while (it.next()) |entry| {
            const str = dom.strings.strings.items[entry.value_ptr.*];
            try dom.strings.map.put(str, entry.value_ptr.*);
        }

        // Copy existing actions
        try dom.actions.appendSlice(self.actions.items);

        // Apply new actions
        for (actions) |action|
            try action.apply(&dom);

        // Append new actions to tracking
        try dom.actions.appendSlice(actions);

        return dom;
    }

    fn createNodeAt(self: *DOM, node_id: u32, node_data: NodeData) !void {
        // Ensure array is large enough to hold node at node_id index (1-based)
        const dummy = NodeData{ .document = .{} };
        while (self.nodes.items.len < node_id) {
            try self.nodes.append(dummy);
        }
        self.nodes.items[node_id - 1] = node_data;
    }

    inline fn getNodeData(self: DOM, node_id: u32) *NodeData {
        return &self.nodes.items[node_id];
    }

    inline fn getNext(self: DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
          .document => 0,
          .element => |e| e.next,
          .attribute => |a| a.next,
          .text => |t| t.next,
          .cdata => |c| c.next,
          .proc_inst => |p| p.next,
          .comment => |co| co.next,
        };
    }
};

// Node wrapper
const Node = struct {
    dom: *const DOM,
    id: u32,

    inline fn nodeData(self: Node) NodeData {
        return self.dom.nodes.items[self.id - 1];
    }

    pub fn nodeType(self: Node) NodeType {
        return std.meta.activeTag(self.nodeData());
    }

    pub fn parentNode(self: Node) ?Node {
        const parent_id = switch (self.nodeData()) {
            .document => 0,
            .element => |e| e.parent,
            .attribute => |a| a.parent,
            .text => |t| t.parent,
            .cdata => |c| c.parent,
            .proc_inst => |p| p.parent,
            .comment => |co| co.parent,
        };
        if (parent_id == 0) return null;
        return Node{ .dom = self.dom, .id = parent_id };
    }

    pub fn firstChild(self: Node) ?Node {
        const child_id = switch (self.nodeData()) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => 0,
        };
        if (child_id == 0) return null;
        return Node{ .dom = self.dom, .id = child_id };
    }

    pub fn lastChild(self: Node) ?Node {
        const child_id = switch (self.nodeData()) {
            .document => |d| d.last_child,
            .element => |e| e.last_child,
            else => 0,
        };
        if (child_id == 0) return null;
        return Node{ .dom = self.dom, .id = child_id };
    }

    pub fn nextSibling(self: Node) ?Node {
        const sibling_id = switch (self.nodeData()) {
            .document => 0,
            .element => |e| e.next,
            .attribute => |a| a.next,
            .text => |t| t.next,
            .cdata => |c| c.next,
            .proc_inst => |p| p.next,
            .comment => |co| co.next,
        };
        if (sibling_id == 0) return null;
        return Node{ .dom = self.dom, .id = sibling_id };
    }

    pub fn childNodes(self: Node) NodeList {
        return NodeList{ .dom = self.dom, .parent_id = self.id };
    }

    pub fn getTagName(self: Node) ?u32 {
        return switch (self.nodeData()) {
            .element => |e| e.tag_name,
            else => null,
        };
    }

    pub fn getAttrName(self: Node) ?u32 {
        return switch (self.nodeData()) {
            .attribute => |a| a.name,
            else => null,
        };
    }

    pub fn getAttrValue(self: Node) ?u32 {
        return switch (self.nodeData()) {
            .attribute => |a| a.value,
            else => null,
        };
    }

    pub fn getTextContent(self: Node) ?u32 {
        return switch (self.nodeData()) {
            .text => |t| t.content,
            .cdata => |c| c.content,
            .proc_inst => |p| p.content,
            .comment => |co| co.content,
            else => null,
        };
    }
};

// NodeList implementation
const NodeList = struct {
    dom: *const DOM,
    parent_id: u32,

    pub fn length(self: NodeList) u32 {
        var count: u32 = 0;
        var current = switch (self.dom.nodes.items[self.parent_id - 1]) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => unreachable,
        };
        while (current != 0) {
            count += 1;
            current = switch (self.dom.nodes.items[current - 1]) {
                .element => |e| e.next,
                .text => |t| t.next,
                .cdata => |c| c.next,
                .proc_inst => |p| p.next,
                .comment => |co| co.next,
                else => unreachable,
            };
        }
        return count;
    }

    pub fn item(self: NodeList, index: u32) ?Node {
        var current = switch (self.dom.nodes.items[self.parent_id - 1]) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => unreachable,
        };
        var i: u32 = 0;
        while (current != 0) {
            if (i == index) {
                return Node{ .dom = self.dom, .id = current };
            }
            i += 1;
            current = switch (self.dom.nodes.items[current - 1]) {
                .element => |e| e.next,
                .text => |t| t.next,
                .cdata => |c| c.next,
                .proc_inst => |p| p.next,
                .comment => |co| co.next,
                else => unreachable,
            };
        }
        return null;
    }
};

// NamedNodeMap implementation
const NamedNodeMap = struct {
    world: *const DOM,
    element_id: u32,

    inline fn first_attr(self: NamedNodeMap) u32 {
        return switch (self.world.nodes.items[self.element_id - 1]) {
            .element => |e| e.first_attr,
            else => unreachable,
        };
    }

    pub fn length(self: NamedNodeMap) u32 {
        var count: u32 = 0;
        var current = self.first_attr();
        while (current != 0) : (current = self.world.getNext(current - 1))
            count += 1;
        return count;
    }

    pub fn item(self: NamedNodeMap, index: u32) ?Node {
        var current = self.first_attr();
        var i: u32 = 0;
        while (current != 0) {
            if (i == index)
                return Node{ .dom = self.world, .id = current };
            i += 1;
            current = self.world.getNext(current - 1);
        }
        return null;
    }

    pub fn getNamedItem(self: NamedNodeMap, name: []const u8) ?Node {
        var current = switch (self.world.nodes.items[self.element_id - 1]) {
            .element => |e| e.first_attr,
            else => 0,
        };
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_name_id = switch (self.world.nodes.items[attr_idx]) {
                .attribute => |a| a.name,
                else => 0,
            };
            const attr_name = self.world.strings.getString(attr_name_id);
            if (std.mem.eql(u8, attr_name, name)) {
                return Node{ .dom = self.world, .id = current };
            }
            current = switch (self.world.nodes.items[attr_idx]) {
                .attribute => |a| a.next,
                else => 0,
            };
        }
        return null;
    }
};

test "append doc with elem" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try dom1.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");

    var dom2 = try dom1.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        appendChildAction(doc.node_id, elem.node_id),
    }, testing.allocator);
    defer dom2.deinit();

    // Verify structure
    if (dom2.nodes.items.len >= doc.node_id) {
        const n = dom2.nodes.items[doc.node_id - 1];
        try testing.expect(std.meta.activeTag(n) == .document);
        try testing.expect(switch (n) {.document => |d| d.first_child, else => undefined} == elem.node_id);
    }

    const elem_node = Node{ .dom = &dom2, .id = elem.node_id };
    try testing.expect(elem_node.nodeType() == .element);
    try testing.expect(elem_node.parentNode().?.id == doc.node_id);
    try testing.expectEqualStrings("div", dom2.strings.getString(elem_node.getTagName().?));
}

test "append doc with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try dom1.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const text = try createTextAction(&builder, "Hello World");

    var dom2 = try dom1.transform(&builder, &[_]Action{
        doc.action,
        text.action,
        appendChildAction(doc.node_id, text.node_id),
    }, testing.allocator);
    defer dom2.deinit();

    const doc_node = dom2.nodes.items[doc.node_id - 1];
    try testing.expect(std.meta.activeTag(doc_node) == .document);
    try testing.expect(switch (doc_node) {.document => |d| d.first_child, else => undefined} == text.node_id);

    const text_node_wrapper = Node{ .dom = &dom2, .id = text.node_id };
    try testing.expect(text_node_wrapper.nodeType() == .text);
    try testing.expect(text_node_wrapper.parentNode().?.id == doc.node_id);
    try testing.expectEqualStrings("Hello World", dom2.strings.getString(text_node_wrapper.getTextContent().?));
}

test "prepend doc with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try dom1.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");
    const text = try createTextAction(&builder, "Hello");

    const actions = [_]Action{
        doc.action,
        elem.action,
        text.action,
        appendChildAction(doc.node_id, elem.node_id),
        prependChildAction(doc.node_id, text.node_id),
    };

    var dom2 = try dom1.transform(&builder, &actions, testing.allocator);
    defer dom2.deinit();

    const doc_node = dom2.nodes.items[doc.node_id - 1];
    try testing.expect(switch (doc_node) {.document => |d| d.first_child, else => undefined} == text.node_id);

    const text_node_wrapper = Node{ .dom = &dom2, .id = text.node_id };
    try testing.expect(switch (dom2.nodes.items[text.node_id - 1]) {.text => |t| t.next, else => undefined} == elem.node_id);
    try testing.expectEqualStrings("Hello", dom2.strings.getString(text_node_wrapper.getTextContent().?));
}

test "append elem with elem" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const parent = try createElementAction(&builder, "div");
    const child = try createElementAction(&builder, "span");

    const actions = [_]Action{
        doc.action,
        parent.action,
        child.action,
        appendChildAction(doc.node_id, parent.node_id),
        appendChildAction(parent.node_id, child.node_id),
    };

    var new_world = try world.transform(&builder, &actions, testing.allocator);
    defer new_world.deinit();

    // Verify structure
    const parent_node_wrapper = Node{ .dom = &new_world, .id = parent.node_id };
    const child_node_wrapper = Node{ .dom = &new_world, .id = child.node_id };

    try testing.expect(switch (new_world.nodes.items[parent.node_id - 1]) {.element => |e| e.first_child, else => undefined} == child.node_id);
    try testing.expect(child_node_wrapper.parentNode().?.id == parent.node_id);
    try testing.expectEqualStrings("div", new_world.strings.getString(parent_node_wrapper.getTagName().?));
    try testing.expectEqualStrings("span", new_world.strings.getString(child_node_wrapper.getTagName().?));
}

test "append elem with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "p");
    const text = try createTextAction(&builder, "Content");

    var new_world = try world.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        text.action,
        appendChildAction(doc.node_id, elem.node_id),
        appendChildAction(elem.node_id, text.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    _ = Node{ .dom = &new_world, .id = elem.node_id };
    const text_node_wrapper = Node{ .dom = &new_world, .id = text.node_id };

    try testing.expect(switch (new_world.nodes.items[elem.node_id - 1]) {.element => |e| e.first_child, else => undefined} == text.node_id);
    try testing.expect(text_node_wrapper.parentNode().?.id == elem.node_id);
    try testing.expectEqualStrings("Content", new_world.strings.getString(text_node_wrapper.getTextContent().?));
}

test "prepend elem with elem" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const parent = try createElementAction(&builder, "ul");
    const child1 = try createElementAction(&builder, "li");
    const child2 = try createElementAction(&builder, "li");

    var new_world = try world.transform(&builder, &[_]Action{
        doc.action,
        parent.action,
        child1.action,
        child2.action,
        appendChildAction(doc.node_id, parent.node_id),
        appendChildAction(parent.node_id, child1.node_id),
        prependChildAction(parent.node_id, child2.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    _ = Node{ .dom = &new_world, .id = parent.node_id };
    try testing.expect(switch (new_world.nodes.items[parent.node_id - 1]) {.element => |e| e.first_child, else => undefined} == child2.node_id);

    const child2_node_wrapper = Node{ .dom = &new_world, .id = child2.node_id };
    try testing.expect(switch (new_world.nodes.items[child2.node_id - 1]) {.element => |e| e.next, else => undefined} == child1.node_id);
    try testing.expect(child2_node_wrapper.parentNode().?.id == parent.node_id);
}

test "prepend elem with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "h1");
    const text1 = try createTextAction(&builder, "World");
    const text2 = try createTextAction(&builder, "Hello ");

    var new_world = try world.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        text1.action,
        text2.action,
        appendChildAction(doc.node_id, elem.node_id),
        appendChildAction(elem.node_id, text1.node_id),
        prependChildAction(elem.node_id, text2.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    _ = Node{ .dom = &new_world, .id = elem.node_id };
    try testing.expect(switch (new_world.nodes.items[elem.node_id - 1]) {.element => |e| e.first_child, else => undefined} == text2.node_id);

    const text2_node_wrapper = Node{ .dom = &new_world, .id = text2.node_id };
    const text1_node_wrapper = Node{ .dom = &new_world, .id = text1.node_id };
    try testing.expect(switch (new_world.nodes.items[text2.node_id - 1]) {.text => |t| t.next, else => undefined} == text1.node_id);
    try testing.expectEqualStrings("Hello ", new_world.strings.getString(text2_node_wrapper.getTextContent().?));
    try testing.expectEqualStrings("World", new_world.strings.getString(text1_node_wrapper.getTextContent().?));
}

test "set attribute on element" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");
    const set_attr = try setAttributeAction(&builder, elem.node_id, "class", "container");

    var new_world = try world.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        appendChildAction(doc.node_id, elem.node_id),
        set_attr,
    }, testing.allocator);
    defer new_world.deinit();

    _ = Node{ .dom = &new_world, .id = elem.node_id };
    const first_attr = switch (new_world.nodes.items[elem.node_id - 1]) {.element => |e| e.first_attr, else => undefined};
    try testing.expect(first_attr != 0);

    const attr_id = first_attr;
    const attr_node_wrapper = Node{ .dom = &new_world, .id = attr_id };
    try testing.expect(attr_node_wrapper.nodeType() == .attribute);
    try testing.expectEqualStrings("class", new_world.strings.getString(attr_node_wrapper.getAttrName().?));
    try testing.expectEqualStrings("container", new_world.strings.getString(attr_node_wrapper.getAttrValue().?));
}

test "remove child" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    var builder = try world.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");
    const text = try createTextAction(&builder, "Hello");

    const actions = [_]Action{
        doc.action,
        elem.action,
        text.action,
        appendChildAction(doc.node_id, elem.node_id),
        appendChildAction(elem.node_id, text.node_id),
        removeChildAction(elem.node_id, text.node_id),
    };

    var new_world = try world.transform(&builder, &actions, testing.allocator);
    defer new_world.deinit();

    _ = Node{ .dom = &new_world, .id = elem.node_id };
    try testing.expect(switch (new_world.nodes.items[elem.node_id - 1]) {.element => |e| e.first_child, else => undefined} == 0);
    try testing.expect(switch (new_world.nodes.items[elem.node_id - 1]) {.element => |e| e.last_child, else => undefined} == 0);

    _ = Node{ .dom = &new_world, .id = text.node_id };
    try testing.expect(switch (new_world.nodes.items[text.node_id - 1]) {.text => |t| t.parent, else => undefined} == 0);
}

test "nodelist" {
    var om1 = try DOM.init(testing.allocator);
    defer om1.deinit();

    var builder = try om1.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");
    const text1 = try createTextAction(&builder, "Hello");
    const text2 = try createTextAction(&builder, "World");

    var dom2 = try om1.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        text1.action,
        text2.action,
        appendChildAction(doc.node_id, elem.node_id),
        appendChildAction(elem.node_id, text1.node_id),
        appendChildAction(elem.node_id, text2.node_id),
    }, testing.allocator);
    defer dom2.deinit();

    const elem_node_wrapper = Node{ .dom = &dom2, .id = elem.node_id };
    const nodes = elem_node_wrapper.childNodes();
    try testing.expect(nodes.length() == 2);
    try testing.expect(nodes.item(0).?.id == text1.node_id);
    try testing.expect(nodes.item(1).?.id == text2.node_id);
}

test "namednodemap" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try dom1.createBuilder(testing.allocator);
    defer builder.deinit();

    const doc = try createDocumentAction(&builder);
    const elem = try createElementAction(&builder, "div");
    const attr1 = try setAttributeAction(&builder, elem.node_id, "class", "container");
    const attr2 = try setAttributeAction(&builder, elem.node_id, "id", "main");

    var dom2 = try dom1.transform(&builder, &[_]Action{
        doc.action,
        elem.action,
        attr1,
        attr2,
    }, testing.allocator);
    defer dom2.deinit();

    const attr_map = NamedNodeMap{ .world = &dom2, .element_id = elem.node_id };
    try testing.expect(attr_map.length() == 2);
    const class_attr = attr_map.getNamedItem("class").?;
    try testing.expectEqualStrings("container", dom2.strings.getString(class_attr.getAttrValue().?));
    const id_attr = attr_map.getNamedItem("id").?;
    try testing.expectEqualStrings("main", dom2.strings.getString(id_attr.getAttrValue().?));
}
