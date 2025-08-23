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
        for (self.strings.items) |str| {
            self.strings.allocator.free(str);
        }
        self.strings.deinit();
        self.map.deinit();
    }

    pub fn intern(self: *Self, str: []const u8) !u32 {
        if (self.map.get(str)) |id| {
            return id;
        }

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

// Forward star representation for tree structure
const NodeData = struct {
    node_type: NodeType,
    tag_name: u32, // interned string id, 0 for non-element nodes
    text_content: u32, // interned string id, 0 for non-text nodes
    parent: u32, // index in nodes array, 0 means no parent
    first_child: u32, // index in nodes array, 0 means no children
    last_child: u32, // index in nodes array, 0 means no children
    next_sibling: u32, // index in nodes array, 0 means no next sibling
    first_attribute: u32, // index in nodes array, 0 means no attributes
    last_attribute: u32, // index in nodes array, 0 means no attributes
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
    text_content: u32, // for create text/cdata/comment/attribute/proc_inst
    attr_name: u32, // for attribute operations
    attr_value: u32, // for set attribute
};

// Main DOM World - copy-on-write container
const DOM = struct {
    // Core data
    nodes: ArrayList(NodeData),
    strings: StringPool,

    // Transformation tracking
    version: u32,
    actions: ArrayList(Action),

    // Node allocation
    next_node_id: u32,

    pub fn init(allocator: Allocator) !DOM {
        var res = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
            .version = 0,
            .actions = ArrayList(Action).init(allocator),
            .next_node_id = 1, // 0 is reserved for "null" references
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

    // Create a new world by applying transformations (copy-on-write)
    pub fn transform(self: *const DOM, actions: []const Action, allocator: Allocator) !DOM {
        var new_world = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
            .version = self.version + 1,
            .actions = ArrayList(Action).init(allocator),
            .next_node_id = self.next_node_id,
        };

        // Copy existing state
        try new_world.nodes.appendSlice(self.nodes.items);

        // Share string pool more efficiently - copy the data structures
        for (self.strings.strings.items) |str| {
            const owned_copy = try allocator.dupe(u8, str);
            try new_world.strings.strings.append(owned_copy);
        }

        // Copy the hash map entries using the new string references
        var iterator = self.strings.map.iterator();
        while (iterator.next()) |entry| {
            const new_str = new_world.strings.strings.items[entry.value_ptr.*];
            try new_world.strings.map.put(new_str, entry.value_ptr.*);
        }

        // Copy existing actions
        try new_world.actions.appendSlice(self.actions.items);

        // Apply new actions
        for (actions) |action| {
            try new_world.applyAction(action);
        }

        return new_world;
    }

    fn applyAction(self: *DOM, action: Action) !void {
        switch (action.action_type) {
            .CreateDocument => {
                const node_data = NodeData{
                    .node_type = .document,
                    .tag_name = 0,
                    .text_content = 0,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateElement => {
                const node_data = NodeData{
                    .node_type = .element,
                    .tag_name = action.tag_name,
                    .text_content = 0,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateAttribute => {
                const node_data = NodeData{
                    .node_type = .attribute,
                    .tag_name = action.tag_name,
                    .text_content = action.text_content,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateText => {
                const node_data = NodeData{
                    .node_type = .text,
                    .tag_name = 0,
                    .text_content = action.text_content,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateCDATA => {
                const node_data = NodeData{
                    .node_type = .cdata,
                    .tag_name = 0,
                    .text_content = action.text_content,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateProcessingInstruction => {
                const node_data = NodeData{
                    .node_type = .proc_inst,
                    .tag_name = action.tag_name,
                    .text_content = action.text_content,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
                try self.createNodeAt(action.target_node, node_data);
            },
            .CreateComment => {
                const node_data = NodeData{
                    .node_type = .comment,
                    .tag_name = 0,
                    .text_content = action.text_content,
                    .parent = 0,
                    .first_child = 0,
                    .last_child = 0,
                    .next_sibling = 0,
                    .first_attribute = 0,
                    .last_attribute = 0,
                };
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

        try self.actions.append(action);
    }

    fn createNodeAt(self: *DOM, node_id: u32, node_data: NodeData) !void {
        // Ensure array is large enough to hold node at node_id index (1-based)
        const dummy = NodeData{
            .node_type = .document,
            .tag_name = 0,
            .text_content = 0,
            .parent = 0,
            .first_child = 0,
            .last_child = 0,
            .next_sibling = 0,
            .first_attribute = 0,
            .last_attribute = 0,
        };
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
        const child_idx = child_id - 1;

        self.nodes.items[child_idx].parent = parent_id;
        self.nodes.items[child_idx].next_sibling = 0;

        if (self.nodes.items[parent_idx].first_child == 0) {
            self.nodes.items[parent_idx].first_child = child_id;
            self.nodes.items[parent_idx].last_child = child_id;
        } else {
            const last_idx = self.nodes.items[parent_idx].last_child - 1;
            self.nodes.items[last_idx].next_sibling = child_id;
            self.nodes.items[parent_idx].last_child = child_id;
        }
    }

    fn prependChildInternal(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const parent_idx = parent_id - 1;
        const child_idx = child_id - 1;

        self.nodes.items[child_idx].parent = parent_id;

        const old_first = self.nodes.items[parent_idx].first_child;
        self.nodes.items[child_idx].next_sibling = old_first;
        self.nodes.items[parent_idx].first_child = child_id;

        if (self.nodes.items[parent_idx].last_child == 0) {
            self.nodes.items[parent_idx].last_child = child_id;
        }
    }

    fn removeChildInternal(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const parent_idx = parent_id - 1;

        var current = self.nodes.items[parent_idx].first_child;
        var prev: u32 = 0;
        while (current != 0) {
            if (current == child_id) {
                const current_idx = current - 1;
                const next = self.nodes.items[current_idx].next_sibling;

                if (prev == 0) {
                    self.nodes.items[parent_idx].first_child = next;
                } else {
                    self.nodes.items[prev - 1].next_sibling = next;
                }

                if (self.nodes.items[parent_idx].last_child == child_id) {
                    self.nodes.items[parent_idx].last_child = prev;
                }

                self.nodes.items[current_idx].parent = 0;
                self.nodes.items[current_idx].next_sibling = 0;
                return;
            }

            prev = current;
            current = self.nodes.items[current - 1].next_sibling;
        }

        return error.ChildNotFound;
    }

    fn setAttributeInternal(self: *DOM, element_id: u32, attr_name_id: u32, attr_value_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const element_idx = element_id - 1;

        // Check if attribute exists
        var current = self.nodes.items[element_idx].first_attribute;
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            if (self.nodes.items[attr_idx].tag_name == attr_name_id) {
                self.nodes.items[attr_idx].text_content = attr_value_id;
                return;
            }
            prev = current;
            current = self.nodes.items[attr_idx].next_sibling;
        }

        // Create new attribute node
        const new_id = self.next_node_id;
        self.next_node_id += 1;

        const dummy = NodeData{
            .node_type = .document,
            .tag_name = 0,
            .text_content = 0,
            .parent = 0,
            .first_child = 0,
            .last_child = 0,
            .next_sibling = 0,
            .first_attribute = 0,
            .last_attribute = 0,
        };
        while (self.nodes.items.len < new_id) {
            try self.nodes.append(dummy);
        }

        const attr_data = NodeData{
            .node_type = .attribute,
            .tag_name = attr_name_id,
            .text_content = attr_value_id,
            .parent = element_id,
            .first_child = 0,
            .last_child = 0,
            .next_sibling = 0,
            .first_attribute = 0,
            .last_attribute = 0,
        };
        self.nodes.items[new_id - 1] = attr_data;

        // Append to attribute list
        if (self.nodes.items[element_idx].first_attribute == 0) {
            self.nodes.items[element_idx].first_attribute = new_id;
            self.nodes.items[element_idx].last_attribute = new_id;
        } else {
            const last_idx = self.nodes.items[element_idx].last_attribute - 1;
            self.nodes.items[last_idx].next_sibling = new_id;
            self.nodes.items[element_idx].last_attribute = new_id;
        }
    }

    fn removeAttributeInternal(self: *DOM, element_id: u32, attr_name_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len) {
            return error.InvalidNodeIndex;
        }

        const element_idx = element_id - 1;

        var current = self.nodes.items[element_idx].first_attribute;
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            if (self.nodes.items[attr_idx].tag_name == attr_name_id) {
                const next = self.nodes.items[attr_idx].next_sibling;

                if (prev == 0) {
                    self.nodes.items[element_idx].first_attribute = next;
                } else {
                    self.nodes.items[prev - 1].next_sibling = next;
                }

                if (self.nodes.items[element_idx].last_attribute == current) {
                    self.nodes.items[element_idx].last_attribute = prev;
                }

                self.nodes.items[attr_idx].parent = 0;
                self.nodes.items[attr_idx].next_sibling = 0;
                return;
            }
            prev = current;
            current = self.nodes.items[attr_idx].next_sibling;
        }

        // Attribute not found, do nothing
    }

    // Helper functions for creating actions
    pub fn createDocumentAction(self: *DOM) !struct { action: Action, node_id: u32 } {
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateDocument,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = 0,
                .text_content = 0,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createElementAction(self: *DOM, tag_name: []const u8) !struct { action: Action, node_id: u32 } {
        const tag_id = try self.strings.intern(tag_name);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateElement,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = tag_id,
                .text_content = 0,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createAttributeAction(self: *DOM, name: []const u8, value: []const u8) !struct { action: Action, node_id: u32 } {
        const name_id = try self.strings.intern(name);
        const value_id = try self.strings.intern(value);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateAttribute,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = name_id,
                .text_content = value_id,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createTextAction(self: *DOM, text: []const u8) !struct { action: Action, node_id: u32 } {
        const text_id = try self.strings.intern(text);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateText,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = 0,
                .text_content = text_id,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createCDATASectionAction(self: *DOM, data: []const u8) !struct { action: Action, node_id: u32 } {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateCDATA,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = 0,
                .text_content = data_id,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createProcessingInstructionAction(self: *DOM, target: []const u8, data: []const u8) !struct { action: Action, node_id: u32 } {
        const target_id = try self.strings.intern(target);
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateProcessingInstruction,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = target_id,
                .text_content = data_id,
                .attr_name = 0,
                .attr_value = 0,
            },
            .node_id = node_id,
        };
    }

    pub fn createCommentAction(self: *DOM, data: []const u8) !struct { action: Action, node_id: u32 } {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        return .{
            .action = Action{
                .action_type = .CreateComment,
                .target_node = node_id,
                .new_node = 0,
                .tag_name = 0,
                .text_content = data_id,
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
            .text_content = 0,
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
            .text_content = 0,
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
            .text_content = 0,
            .attr_name = 0,
            .attr_value = 0,
        };
    }

    pub fn setAttributeAction(self: *DOM, element_id: u32, name: []const u8, value: []const u8) !Action {
        const name_id = try self.strings.intern(name);
        const value_id = try self.strings.intern(value);

        return Action{
            .action_type = .SetAttribute,
            .target_node = element_id,
            .new_node = 0,
            .tag_name = 0,
            .text_content = 0,
            .attr_name = name_id,
            .attr_value = value_id,
        };
    }

    pub fn removeAttributeAction(self: *DOM, element_id: u32, name: []const u8) !Action {
        const name_id = try self.strings.intern(name);

        return Action{
            .action_type = .RemoveAttribute,
            .target_node = element_id,
            .new_node = 0,
            .tag_name = 0,
            .text_content = 0,
            .attr_name = name_id,
            .attr_value = 0,
        };
    }

    // Query helpers
    pub fn getNode(self: *const DOM, node_id: u32) ?*const NodeData {
        if (node_id == 0 or node_id > self.nodes.items.len) return null;
        return &self.nodes.items[node_id - 1]; // node_id is 1-based
    }

    pub fn getTagName(self: *const DOM, node_id: u32) ?[]const u8 {
        if (self.getNode(node_id)) |node| {
            if (node.tag_name != 0) {
                return self.strings.getString(node.tag_name);
            }
        }
        return null;
    }

    pub fn getTextContent(self: *const DOM, node_id: u32) ?[]const u8 {
        if (self.getNode(node_id)) |node| {
            if (node.text_content != 0) {
                return self.strings.getString(node.text_content);
            }
        }
        return null;
    }
};

// Node wrapper
const Node = struct {
    world: *const DOM,
    id: u32,

    pub fn nodeType(self: Node) NodeType {
        return self.world.nodes.items[self.id - 1].node_type;
    }

    pub fn parentNode(self: Node) ?Node {
        const parent_id = self.world.nodes.items[self.id - 1].parent;
        if (parent_id == 0) return null;
        return Node{ .world = self.world, .id = parent_id };
    }

    pub fn firstChild(self: Node) ?Node {
        const child_id = self.world.nodes.items[self.id - 1].first_child;
        if (child_id == 0) return null;
        return Node{ .world = self.world, .id = child_id };
    }

    pub fn lastChild(self: Node) ?Node {
        const child_id = self.world.nodes.items[self.id - 1].last_child;
        if (child_id == 0) return null;
        return Node{ .world = self.world, .id = child_id };
    }

    pub fn nextSibling(self: Node) ?Node {
        const sibling_id = self.world.nodes.items[self.id - 1].next_sibling;
        if (sibling_id == 0) return null;
        return Node{ .world = self.world, .id = sibling_id };
    }

    pub fn childNodes(self: Node) NodeList {
        return NodeList{ .world = self.world, .parent_id = self.id };
    }
};

// NodeList implementation
const NodeList = struct {
    world: *const DOM,
    parent_id: u32,

    pub fn length(self: NodeList) u32 {
        var count: u32 = 0;
        var current = self.world.nodes.items[self.parent_id - 1].first_child;
        while (current != 0) {
            count += 1;
            current = self.world.nodes.items[current - 1].next_sibling;
        }
        return count;
    }

    pub fn item(self: NodeList, index: u32) ?Node {
        var current = self.world.nodes.items[self.parent_id - 1].first_child;
        var i: u32 = 0;
        while (current != 0) {
            if (i == index) {
                return Node{ .world = self.world, .id = current };
            }
            i += 1;
            current = self.world.nodes.items[current - 1].next_sibling;
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
        var current = self.world.nodes.items[self.element_id - 1].first_attribute;
        while (current != 0) {
            count += 1;
            current = self.world.nodes.items[current - 1].next_sibling;
        }
        return count;
    }

    pub fn item(self: NamedNodeMap, index: u32) ?Node {
        var current = self.world.nodes.items[self.element_id - 1].first_attribute;
        var i: u32 = 0;
        while (current != 0) {
            if (i == index) {
                return Node{ .world = self.world, .id = current };
            }
            i += 1;
            current = self.world.nodes.items[current - 1].next_sibling;
        }
        return null;
    }

    pub fn getNamedItem(self: NamedNodeMap, name: []const u8) ?Node {
        var current = self.world.nodes.items[self.element_id - 1].first_attribute;
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_name = self.world.strings.getString(self.world.nodes.items[attr_idx].tag_name);
            if (std.mem.eql(u8, attr_name, name)) {
                return Node{ .world = self.world, .id = current };
            }
            current = self.world.nodes.items[attr_idx].next_sibling;
        }
        return null;
    }
};

test "append doc with elem" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    const doc = try dom1.createDocumentAction();
    const elem = try dom1.createElementAction("div");

    var dom2 = try dom1.transform(&[_]Action{
        doc.action,
        elem.action,
        DOM.appendChildAction(doc.node_id, elem.node_id)
    }, testing.allocator);
    defer dom2.deinit();

    // Verify structure
    if (dom2.getNode(doc.node_id)) |n| {
      try testing.expect(n.node_type == .document);
      try testing.expect(n.first_child == elem.node_id);
    }

    if (dom2.getNode(elem.node_id)) |n| {
      try testing.expect(n.node_type == .element);
      try testing.expect(n.parent == doc.node_id);
      try testing.expectEqualStrings("div", dom2.getTagName(elem.node_id).?);
    }
}

test "append doc with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const text = try world.createTextAction("Hello World");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        text.action,
        DOM.appendChildAction(doc.node_id, text.node_id)
    }, testing.allocator);
    defer new_world.deinit();

    const doc_node = new_world.getNode(doc.node_id).?;
    const text_node = new_world.getNode(text.node_id).?;

    try testing.expect(doc_node.node_type == .document);
    try testing.expect(doc_node.first_child == text.node_id);
    try testing.expect(text_node.node_type == .text);
    try testing.expect(text_node.parent == doc.node_id);
    try testing.expectEqualStrings("Hello World", new_world.getTextContent(text.node_id).?);
}

test "prepend doc with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("div");
    const text = try world.createTextAction("Hello");

    const actions = [_]Action{
        doc.action,
        elem.action,
        text.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        DOM.prependChildAction(doc.node_id, text.node_id),
    };

    var new_world = try world.transform(&actions, testing.allocator);
    defer new_world.deinit();

    const doc_node = new_world.getNode(doc.node_id).?;
    try testing.expect(doc_node.first_child == text.node_id);

    const text_node = new_world.getNode(text.node_id).?;
    try testing.expect(text_node.next_sibling == elem.node_id);
    try testing.expectEqualStrings("Hello", new_world.getTextContent(text.node_id).?);
}

test "append elem with elem" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const parent = try world.createElementAction("div");
    const child = try world.createElementAction("span");

    const actions = [_]Action{
        doc.action,
        parent.action,
        child.action,
        DOM.appendChildAction(doc.node_id, parent.node_id),
        DOM.appendChildAction(parent.node_id, child.node_id),
    };

    var new_world = try world.transform(&actions, testing.allocator);
    defer new_world.deinit();

    // Verify structure
    const parent_node = new_world.getNode(parent.node_id).?;
    const child_node = new_world.getNode(child.node_id).?;

    try testing.expect(parent_node.first_child == child.node_id);
    try testing.expect(child_node.parent == parent.node_id);
    try testing.expectEqualStrings("div", new_world.getTagName(parent.node_id).?);
    try testing.expectEqualStrings("span", new_world.getTagName(child.node_id).?);
}

test "append elem with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("p");
    const text = try world.createTextAction("Content");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        elem.action,
        text.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        DOM.appendChildAction(elem.node_id, text.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    const elem_node = new_world.getNode(elem.node_id).?;
    const text_node = new_world.getNode(text.node_id).?;

    try testing.expect(elem_node.first_child == text.node_id);
    try testing.expect(text_node.parent == elem.node_id);
    try testing.expectEqualStrings("Content", new_world.getTextContent(text.node_id).?);
}

test "prepend elem with elem" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const parent = try world.createElementAction("ul");
    const child1 = try world.createElementAction("li");
    const child2 = try world.createElementAction("li");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        parent.action,
        child1.action,
        child2.action,
        DOM.appendChildAction(doc.node_id, parent.node_id),
        DOM.appendChildAction(parent.node_id, child1.node_id),
        DOM.prependChildAction(parent.node_id, child2.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    const parent_node = new_world.getNode(parent.node_id).?;
    try testing.expect(parent_node.first_child == child2.node_id);

    const child2_node = new_world.getNode(child2.node_id).?;
    try testing.expect(child2_node.next_sibling == child1.node_id);
    try testing.expect(child2_node.parent == parent.node_id);
}

test "prepend elem with text" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("h1");
    const text1 = try world.createTextAction("World");
    const text2 = try world.createTextAction("Hello ");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        elem.action,
        text1.action,
        text2.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        DOM.appendChildAction(elem.node_id, text1.node_id),
        DOM.prependChildAction(elem.node_id, text2.node_id),
    }, testing.allocator);
    defer new_world.deinit();

    const elem_node = new_world.getNode(elem.node_id).?;
    try testing.expect(elem_node.first_child == text2.node_id);

    const text2_node = new_world.getNode(text2.node_id).?;
    try testing.expect(text2_node.next_sibling == text1.node_id);
    try testing.expectEqualStrings("Hello ", new_world.getTextContent(text2.node_id).?);
    try testing.expectEqualStrings("World", new_world.getTextContent(text1.node_id).?);
}

test "set attribute on element" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("div");
    const set_attr = try world.setAttributeAction(elem.node_id, "class", "container");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        elem.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        set_attr,
    }, testing.allocator);
    defer new_world.deinit();

    const elem_node = new_world.getNode(elem.node_id).?;
    try testing.expect(elem_node.first_attribute != 0);

    const attr_id = elem_node.first_attribute;
    const attr_node = new_world.getNode(attr_id).?;
    try testing.expect(attr_node.node_type == .attribute);
    try testing.expectEqualStrings("class", new_world.getTagName(attr_id).?);
    try testing.expectEqualStrings("container", new_world.getTextContent(attr_id).?);
}

test "remove child" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("div");
    const text = try world.createTextAction("Hello");

    const actions = [_]Action{
        doc.action,
        elem.action,
        text.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        DOM.appendChildAction(elem.node_id, text.node_id),
        DOM.removeChildAction(elem.node_id, text.node_id),
    };

    var new_world = try world.transform(&actions, testing.allocator);
    defer new_world.deinit();

    const elem_node = new_world.getNode(elem.node_id).?;
    try testing.expect(elem_node.first_child == 0);
    try testing.expect(elem_node.last_child == 0);

    const text_node = new_world.getNode(text.node_id).?;
    try testing.expect(text_node.parent == 0);
}

test "nodelist" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("div");
    const text1 = try world.createTextAction("Hello");
    const text2 = try world.createTextAction("World");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        elem.action,
        text1.action,
        text2.action,
        DOM.appendChildAction(doc.node_id, elem.node_id),
        DOM.appendChildAction(elem.node_id, text1.node_id),
        DOM.appendChildAction(elem.node_id, text2.node_id)
    }, testing.allocator);
    defer new_world.deinit();

    const elem_node_wrapper = Node{ .world = &new_world, .id = elem.node_id };
    const nodes = elem_node_wrapper.childNodes();
    try testing.expect(nodes.length() == 2);
    try testing.expect(nodes.item(0).?.id == text1.node_id);
    try testing.expect(nodes.item(1).?.id == text2.node_id);
}

test "namednodemap" {
    var world = try DOM.init(testing.allocator);
    defer world.deinit();

    const doc = try world.createDocumentAction();
    const elem = try world.createElementAction("div");
    const attr1 = try world.setAttributeAction(elem.node_id, "class", "container");
    const attr2 = try world.setAttributeAction(elem.node_id, "id", "main");

    var new_world = try world.transform(&[_]Action{
        doc.action,
        elem.action,
        attr1,
        attr2,
    }, testing.allocator);
    defer new_world.deinit();

    const attr_map = NamedNodeMap{ .world = &new_world, .element_id = elem.node_id };
    try testing.expect(attr_map.length() == 2);
    const class_attr = attr_map.getNamedItem("class").?;
    try testing.expectEqualStrings("container", new_world.getTextContent(class_attr.id).?);
    const id_attr = attr_map.getNamedItem("id").?;
    try testing.expectEqualStrings("main", new_world.getTextContent(id_attr.id).?);
}
