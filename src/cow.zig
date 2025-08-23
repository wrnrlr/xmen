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
const NodeType = enum(u8) {
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

const Action = struct {
    action_type: ActionType,
    target_node: u32, // node index
    new_node: u32, // for append/prepend/remove child operations
    tag_name: u32, // for create element/attribute/proc_inst
    content: u32, // for create text/cdata/comment/attribute/proc_inst
    attr_name: u32, // for attribute operations
    attr_value: u32, // for set attribute
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
        .action = Action{
            .action_type = .CreateDocument,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = 0,
            .content = 0,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createElementAction(builder: *Builder, tag_name: []const u8) !struct { action: Action, node_id: u32 } {
    const tag_id = try builder.strings.intern(tag_name);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateElement,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = tag_id,
            .content = 0,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createAttributeAction(builder: *Builder, name: []const u8, value: []const u8) !struct { action: Action, node_id: u32 } {
    const name_id = try builder.strings.intern(name);
    const value_id = try builder.strings.intern(value);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateAttribute,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = name_id,
            .content = value_id,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createTextAction(builder: *Builder, text: []const u8) !struct { action: Action, node_id: u32 } {
    const text_id = try builder.strings.intern(text);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateText,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = 0,
            .content = text_id,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createCDATASectionAction(builder: *Builder, data: []const u8) !struct { action: Action, node_id: u32 } {
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateCDATA,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = 0,
            .content = data_id,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createProcessingInstructionAction(builder: *Builder, target: []const u8, data: []const u8) !struct { action: Action, node_id: u32 } {
    const target_id = try builder.strings.intern(target);
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateProcessingInstruction,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = target_id,
            .content = data_id,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn createCommentAction(builder: *Builder, data: []const u8) !struct { action: Action, node_id: u32 } {
    const data_id = try builder.strings.intern(data);
    const node_id = builder.next_node_id;
    builder.next_node_id += 1;

    return .{
        .action = Action{
            .action_type = .CreateComment,
            .target_node = node_id,
            .new_node = 0,
            .tag_name = 0,
            .content = data_id,
            .attr_name = 0,
            .attr_value = 0,
        },
        .node_id = node_id,
    };
}

pub fn appendChildAction(parent_id: u32, child_id: u32) Action {
    return Action{
        .action_type = .AppendChild,
        .target_node = parent_id,
        .new_node = child_id,
        .tag_name = 0,
        .content = 0,
        .attr_name = 0,
        .attr_value = 0,
    };
}

pub fn prependChildAction(parent_id: u32, child_id: u32) Action {
    return Action{
        .action_type = .PrependChild,
        .target_node = parent_id,
        .new_node = child_id,
        .tag_name = 0,
        .content = 0,
        .attr_name = 0,
        .attr_value = 0,
    };
}

pub fn removeChildAction(parent_id: u32, child_id: u32) Action {
    return Action{
        .action_type = .RemoveChild,
        .target_node = parent_id,
        .new_node = child_id,
        .tag_name = 0,
        .content = 0,
        .attr_name = 0,
        .attr_value = 0,
    };
}

pub fn setAttributeAction(builder: *Builder, element_id: u32, name: []const u8, value: []const u8) !Action {
    const name_id = try builder.strings.intern(name);
    const value_id = try builder.strings.intern(value);

    return Action{
        .action_type = .SetAttribute,
        .target_node = element_id,
        .new_node = 0,
        .tag_name = 0,
        .content = 0,
        .attr_name = name_id,
        .attr_value = value_id,
    };
}

pub fn removeAttributeAction(builder: *Builder, element_id: u32, name: []const u8) !Action {
    const name_id = try builder.strings.intern(name);

    return Action{
        .action_type = .RemoveAttribute,
        .target_node = element_id,
        .new_node = 0,
        .tag_name = 0,
        .content = 0,
        .attr_name = name_id,
        .attr_value = 0,
    };
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
        for (actions) |action| {
            try dom.applyAction(action);
        }

        // Append new actions to tracking
        try dom.actions.appendSlice(actions);

        return dom;
    }

    fn applyAction(self: *DOM, action: Action) !void {
        switch (action.action_type) {
            .CreateElement => {
                const node_data = NodeData{ .element = .{ .tag_name = action.tag_name } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateAttribute => {
                const node_data = NodeData{ .attribute = .{ .name = action.tag_name, .value = action.content } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateText => {
                const node_data = NodeData{ .text = .{ .content = action.content } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateCDATA => {
                const node_data = NodeData{ .cdata = .{ .content = action.content } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateProcessingInstruction => {
                const node_data = NodeData{ .proc_inst = .{ .content = action.content } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateComment => {
                const node_data = NodeData{ .comment = .{ .content = action.content } };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateDocument => {
                const node_data = NodeData{ .document = .{} };
                try self.createNodeAt(action.target_node, node_data);
            },
            .AppendChild => {
                try self.appendChildInternal(action.target_node, action.new_node);
            },
            .PrependChild => {
                try self.prependChildInternal(action.target_node, action.new_node);
            },
            .RemoveChild => {
                try self.removeChildInternal(action.target_node, action.new_node);
            },
            .SetAttribute => {
                try self.setAttributeInternal(action.target_node, action.attr_name, action.attr_value);
            },
            .RemoveAttribute => {
                try self.removeAttributeInternal(action.target_node, action.attr_name);
            },
        }
    }

    fn createNodeAt(self: *DOM, node_id: u32, node_data: NodeData) !void {
        // Ensure array is large enough to hold node at node_id index (1-based)
        const dummy = NodeData{ .document = .{} };
        while (self.nodes.items.len < node_id) {
            try self.nodes.append(dummy);
        }
        self.nodes.items[node_id - 1] = node_data;
    }

    fn appendChildInternal(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const parent_idx = parent_id - 1;
        const parent_data = &self.nodes.items[parent_idx];

        const child_idx = child_id - 1;
        const child_data = &self.nodes.items[child_idx];

        // Set child parent and next = 0
        switch (child_data.*) {
            .element => |*e| {
                e.parent = parent_id;
                e.next = 0;
            },
            .text => |*t| {
                t.parent = parent_id;
                t.next = 0;
            },
            .cdata => |*c| {
                c.parent = parent_id;
                c.next = 0;
            },
            .proc_inst => |*p| {
                p.parent = parent_id;
                p.next = 0;
            },
            .comment => |*co| {
                co.parent = parent_id;
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
                    d.first_child = child_id;
                    d.last_child = child_id;
                },
                .element => |*e| {
                    e.first_child = child_id;
                    e.last_child = child_id;
                },
                else => unreachable,
            }
        } else {
            const last_child = switch (parent_data.*) {
                .document => |d| d.last_child,
                .element => |e| e.last_child,
                else => unreachable,
            };
            const last_data = &self.nodes.items[last_child - 1];
            switch (last_data.*) {
                .element => |*e| e.next = child_id,
                .text => |*t| t.next = child_id,
                .cdata => |*c| c.next = child_id,
                .proc_inst => |*p| p.next = child_id,
                .comment => |*co| co.next = child_id,
                else => return error.InvalidChildType,
            }
            switch (parent_data.*) {
                .document => |*d| d.last_child = child_id,
                .element => |*e| e.last_child = child_id,
                else => unreachable,
            }
        }
    }

    fn prependChildInternal(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const parent_idx = parent_id - 1;
        const parent_data = &self.nodes.items[parent_idx];

        const child_idx = child_id - 1;
        const child_data = &self.nodes.items[child_idx];

        // Set child parent
        switch (child_data.*) {
            .element => |*e| e.parent = parent_id,
            .text => |*t| t.parent = parent_id,
            .cdata => |*c| c.parent = parent_id,
            .proc_inst => |*p| p.parent = parent_id,
            .comment => |*co| co.parent = parent_id,
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
            .document => |*d| d.first_child = child_id,
            .element => |*e| e.first_child = child_id,
            else => unreachable,
        }

        if (switch (parent_data.*) {
            .document => |d| d.last_child,
            .element => |e| e.last_child,
            else => unreachable,
        } == 0) {
            switch (parent_data.*) {
                .document => |*d| d.last_child = child_id,
                .element => |*e| e.last_child = child_id,
                else => unreachable,
            }
        }
    }

    fn removeChildInternal(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const parent_idx = parent_id - 1;
        const parent_data = &self.nodes.items[parent_idx];

        var current = switch (parent_data.*) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => return error.InvalidParentType,
        };
        var prev: u32 = 0;
        while (current != 0) {
            if (current == child_id) {
                const current_idx = current - 1;
                const current_data = &self.nodes.items[current_idx];
                const next = switch (current_data.*) {
                    .element => |e| e.next,
                    .text => |t| t.next,
                    .cdata => |c| c.next,
                    .proc_inst => |p| p.next,
                    .comment => |co| co.next,
                    else => return error.InvalidChildType,
                };

                if (prev == 0) {
                    switch (parent_data.*) {
                        .document => |*d| d.first_child = next,
                        .element => |*e| e.first_child = next,
                        else => unreachable,
                    }
                } else {
                    const prev_data = &self.nodes.items[prev - 1];
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
                } == child_id) {
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
            current = switch (self.nodes.items[current - 1]) {
                .element => |e| e.next,
                .text => |t| t.next,
                .cdata => |c| c.next,
                .proc_inst => |p| p.next,
                .comment => |co| co.next,
                else => return error.InvalidChildType,
            };
        }

        return error.ChildNotFound;
    }

    fn setAttributeInternal(self: *DOM, element_id: u32, name_id: u32, value_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const element_idx = element_id - 1;
        const element_data = &self.nodes.items[element_idx];

        const first_attr = switch (element_data.*) {
            .element => |e| e.first_attr,
            else => return error.NotElement,
        };

        // Check if attribute exists
        var current = first_attr;
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_data = &self.nodes.items[attr_idx];
            const tag_name = switch (attr_data.*) {
                .attribute => |a| a.name,
                else => return error.InvalidAttributeType,
            };
            if (tag_name == name_id) {
                switch (attr_data.*) {
                    .attribute => |*a| a.value = value_id,
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

        // Create new attribute node
        const new_id:u32 = @intCast(self.nodes.items.len + 1);
        const attr_data = NodeData{ .attribute = .{ .name = name_id, .value = value_id, .parent = element_id } };
        try self.createNodeAt(new_id, attr_data);

        // Append to attribute list
        switch (element_data.*) {
            .element => |*e| {
                if (e.first_attr == 0) {
                    e.first_attr = new_id;
                    e.last_attr = new_id;
                } else {
                    const last_idx = e.last_attr - 1;
                    const last_attr_data = &self.nodes.items[last_idx];
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

    fn removeAttributeInternal(self: *DOM, element_id: u32, attr_name_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len)
            return error.InvalidNodeIndex;

        const element_idx = element_id - 1;
        const element_data = &self.nodes.items[element_idx];

        var current = switch (element_data.*) {
            .element => |e| e.first_attr,
            else => return error.NotElement,
        };
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_data = &self.nodes.items[attr_idx];
            const tag_name = switch (attr_data.*) {
                .attribute => |a| a.name,
                else => return error.InvalidAttributeType,
            };
            if (tag_name == attr_name_id) {
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
                    const prev_data = &self.nodes.items[prev - 1];
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

    // Query helpers
    pub fn getNode(self: *const DOM, node_id: u32) ?*const NodeData {
        if (node_id == 0 or node_id > self.nodes.items.len) return null;
        return &self.nodes.items[node_id - 1];
    }

    pub fn getTagName(self: *const DOM, node_id: u32) ?[]const u8 {
        return switch (self.getNode(node_id).?.*) {
            .element => |e| self.strings.getString(e.tag_name),
            else => unreachable
        };
    }

    pub fn getAttrName(self: *const DOM, node_id: u32) ?[]const u8 {
        return switch (self.getNode(node_id).?.*) {
            .attribute => |e| self.strings.getString(e.name),
            else => unreachable
        };
    }

    pub fn getAttrValue(self: *const DOM, node_id: u32) ?[]const u8 {
        return switch (self.getNode(node_id).?.*) {
            .attribute => |e| self.strings.getString(e.value),
            else => unreachable
        };
    }

    pub fn getTextContent(self: *const DOM, node_id: u32) ?[]const u8 {
        if (self.getNode(node_id)) |node| {
            const text_id = switch (node.*) {
                .text => |t| t.content,
                .cdata => |c| c.content,
                .proc_inst => |p| p.content,
                .comment => |co| co.content,
                else => return null,
            };
            return self.strings.getString(text_id);
        }
        return null;
    }
};

// Node wrapper
const Node = struct {
    dom: *const DOM,
    id: u32,

    inline fn node(self: Node) ?NodeData {
      return self.dom.nodes.items[self.id - 1];
    }

    pub fn nodeType(self: Node) NodeType {
        return std.meta.activeTag(self.node());
    }

    pub fn parentNode(self: Node) ?Node {
        const parent_id = switch (self.node()) {
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
        const child_id = switch (self.node()) {
            .document => |d| d.first_child,
            .element => |e| e.first_child,
            else => 0,
        };
        if (child_id == 0) return null;
        return Node{ .dom = self.dom, .id = child_id };
    }

    pub fn lastChild(self: Node) ?Node {
        const child_id = switch (self.node()) {
            .document => |d| d.last_child,
            .element => |e| e.last_child,
            else => 0,
        };
        if (child_id == 0) return null;
        return Node{ .dom = self.dom, .id = child_id };
    }

    pub fn nextSibling(self: Node) ?Node {
        const sibling_id = switch (self.node()) {
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

    pub fn length(self: NamedNodeMap) u32 {
        var count: u32 = 0;
        var current = switch (self.world.nodes.items[self.element_id - 1]) {
            .element => |e| e.first_attr,
            else => unreachable,
        };
        while (current != 0) {
            count += 1;
            current = switch (self.world.nodes.items[current - 1]) {
                .attribute => |a| a.next,
                else => unreachable,
            };
        }
        return count;
    }

    pub fn item(self: NamedNodeMap, index: u32) ?Node {
        var current = switch (self.world.nodes.items[self.element_id - 1]) {
            .element => |e| e.first_attr,
            else => 0,
        };
        var i: u32 = 0;
        while (current != 0) {
            if (i == index) {
                return Node{ .dom = self.world, .id = current };
            }
            i += 1;
            current = switch (self.world.nodes.items[current - 1]) {
                .attribute => |a| a.next,
                else => 0,
            };
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
    if (dom2.getNode(doc.node_id)) |n| {
        try testing.expect(std.meta.activeTag(n.*) == .document);
        try testing.expect(switch (n.*) {.document => |d| d.first_child, else => undefined} == elem.node_id);
    }

    if (dom2.getNode(elem.node_id)) |n| {
        try testing.expect(std.meta.activeTag(n.*) == .element);
        try testing.expect(switch (n.*) {.element => |e| e.parent, else => undefined} == doc.node_id);
        try testing.expectEqualStrings("div", dom2.getTagName(elem.node_id).?);
    }
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

    const doc_node = dom2.getNode(doc.node_id).?;
    const text_node = dom2.getNode(text.node_id).?;

    try testing.expect(std.meta.activeTag(doc_node.*) == .document);
    try testing.expect(switch (doc_node.*) {.document => |d| d.first_child, else => undefined} == text.node_id);
    try testing.expect(std.meta.activeTag(text_node.*) == .text);
    try testing.expect(switch (text_node.*) {.text => |t| t.parent, else => undefined} == doc.node_id);
    try testing.expectEqualStrings("Hello World", dom2.getTextContent(text.node_id).?);
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

    const doc_node = dom2.getNode(doc.node_id).?;
    try testing.expect(switch (doc_node.*) {.document => |d| d.first_child, else => undefined} == text.node_id);

    const text_node = dom2.getNode(text.node_id).?;
    try testing.expect(switch (text_node.*) {.text => |t| t.next, else => undefined} == elem.node_id);
    try testing.expectEqualStrings("Hello", dom2.getTextContent(text.node_id).?);
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
    const parent_node = new_world.getNode(parent.node_id).?;
    const child_node = new_world.getNode(child.node_id).?;

    try testing.expect(switch (parent_node.*) {.element => |e| e.first_child, else => undefined} == child.node_id);
    try testing.expect(switch (child_node.*) {.element => |e| e.parent, else => undefined} == parent.node_id);
    try testing.expectEqualStrings("div", new_world.getTagName(parent.node_id).?);
    try testing.expectEqualStrings("span", new_world.getTagName(child.node_id).?);
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

    const elem_node = new_world.getNode(elem.node_id).?;
    const text_node = new_world.getNode(text.node_id).?;

    try testing.expect(switch (elem_node.*) {.element => |e| e.first_child, else => undefined} == text.node_id);
    try testing.expect(switch (text_node.*) {.text => |t| t.parent, else => undefined} == elem.node_id);
    try testing.expectEqualStrings("Content", new_world.getTextContent(text.node_id).?);
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

    const parent_node = new_world.getNode(parent.node_id).?;
    try testing.expect(switch (parent_node.*) {.element => |e| e.first_child, else => undefined} == child2.node_id);

    const child2_node = new_world.getNode(child2.node_id).?;
    try testing.expect(switch (child2_node.*) {.element => |e| e.next, else => undefined} == child1.node_id);
    try testing.expect(switch (child2_node.*) {.element => |e| e.parent, else => undefined} == parent.node_id);
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

    const elem_node = new_world.getNode(elem.node_id).?;
    try testing.expect(switch (elem_node.*) {.element => |e| e.first_child, else => undefined} == text2.node_id);

    const text2_node = new_world.getNode(text2.node_id).?;
    try testing.expect(switch (text2_node.*) {.text => |t| t.next, else => undefined} == text1.node_id);
    try testing.expectEqualStrings("Hello ", new_world.getTextContent(text2.node_id).?);
    try testing.expectEqualStrings("World", new_world.getTextContent(text1.node_id).?);
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

    const elem_node = new_world.getNode(elem.node_id).?;
    const first_attr = switch (elem_node.*) {.element => |e| e.first_attr, else => undefined};
    try testing.expect(first_attr != 0);

    const attr_id = first_attr;
    const attr_node = new_world.getNode(attr_id).?;
    try testing.expect(std.meta.activeTag(attr_node.*) == .attribute);
    try testing.expectEqualStrings("class", new_world.getAttrName(attr_id).?);
    try testing.expectEqualStrings("container", new_world.getAttrValue(attr_id).?);
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

    const elem_node = new_world.getNode(elem.node_id).?;
    try testing.expect(switch (elem_node.*) {.element => |e| e.first_child, else => undefined} == 0);
    try testing.expect(switch (elem_node.*) {.element => |e| e.last_child, else => undefined} == 0);

    const text_node = new_world.getNode(text.node_id).?;
    try testing.expect(switch (text_node.*) {.text => |t| t.parent, else => undefined} == 0);
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
    try testing.expectEqualStrings("container", dom2.getAttrValue(class_attr.id).?);
    const id_attr = attr_map.getNamedItem("id").?;
    try testing.expectEqualStrings("main", dom2.getAttrValue(id_attr.id).?);
}
