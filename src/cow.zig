const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

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

const DOM = struct {
    nodes: ArrayList(NodeData),
    strings: StringPool,

    pub fn init(allocator: Allocator) !DOM {
        var res = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
        };
        const empty = try allocator.dupe(u8, "");
        try res.strings.strings.append(empty);
        return res;
    }

    pub fn deinit(self: *DOM) void {
        self.nodes.deinit();
        self.strings.deinit();
    }

    // Clone nodes and swap in a complete StringPool clone from builder
    fn cloneWithBuilderStrings(self: *const DOM, allocator: Allocator, builder_strings: *const StringPool) !DOM {
        var dom = DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
        };
        try dom.nodes.appendSlice(self.nodes.items);

        // Copy builder strings (already includes originals)
        for (builder_strings.strings.items) |s| {
            const dup = try allocator.dupe(u8, s);
            try dom.strings.strings.append(dup);
        }
        var it = builder_strings.map.iterator();
        while (it.next()) |entry| {
            const s = dom.strings.strings.items[entry.value_ptr.*];
            try dom.strings.map.put(s, entry.value_ptr.*);
        }
        return dom;
    }

    fn createNodeAt(self: *DOM, node_id: u32, node_data: NodeData) !void {
        const dummy = NodeData{ .document = .{} };
        while (self.nodes.items.len < node_id) {
            try self.nodes.append(dummy);
        }
        self.nodes.items[node_id - 1] = node_data;
    }

    inline fn getNext(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .document => 0,
            .element => |e| e.next,
            .attribute => |a| a.next,
            .text => |t| t.next,
            .cdata => |c| c.next,
            .proc_inst => |p| p.next,
            .comment => |co| co.next,
        };
    }

    fn setNext(self: *DOM, node_idx: u32, val: u32) void {
        switch (self.nodes.items[node_idx]) {
            .document => unreachable,
            .element => |*e| e.next = val,
            .attribute => |*a| a.next = val,
            .text => |*t| t.next = val,
            .cdata => |*c| c.next = val,
            .proc_inst => |*p| p.next = val,
            .comment => |*co| co.next = val,
        }
    }

    fn getParent(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .document => 0,
            .element => |e| e.parent,
            .attribute => |a| a.parent,
            .text => |t| t.parent,
            .cdata => |c| c.parent,
            .proc_inst => |p| p.parent,
            .comment => |co| co.parent,
        };
    }

    fn setParent(self: *DOM, node_idx: u32, val: u32) void {
        switch (self.nodes.items[node_idx]) {
            .document => unreachable,
            .element => |*e| e.parent = val,
            .attribute => |*a| a.parent = val,
            .text => |*t| t.parent = val,
            .cdata => |*c| c.parent = val,
            .proc_inst => |*p| p.parent = val,
            .comment => |*co| co.parent = val,
        }
    }

    fn firstChild(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .element => |e| e.first_child,
            .document => |d| d.first_child,
            else => unreachable,
        };
    }

    fn setFirstChild(self: *DOM, node_idx: u32, child_id: u32) void {
        switch (self.nodes.items[node_idx]) {
            .element => |*e| e.first_child = child_id,
            .document => |*d| d.first_child = child_id,
            else => unreachable,
        }
    }

    fn lastChild(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .element => |e| e.last_child,
            .document => |d| d.last_child,
            else => unreachable,
        };
    }

    fn setLastChild(self: *DOM, node_idx: u32, child_id: u32) void {
        switch (self.nodes.items[node_idx]) {
            .element => |*e| e.last_child = child_id,
            .document => |*d| d.last_child = child_id,
            else => unreachable,
        }
    }

    fn firstAttr(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .element => |e| e.first_attr,
            else => unreachable,
        };
    }

    fn setFirstAttr(self: *DOM, node_idx: u32, attr_id: u32) void {
        switch (self.nodes.items[node_idx]) {
            .element => |*e| e.first_attr = attr_id,
            else => unreachable,
        }
    }

    fn setLastAttr(self: *DOM, node_idx: u32, attr_id: u32) void {
        switch (self.nodes.items[node_idx]) {
            .element => |*e| e.last_attr = attr_id,
            else => unreachable,
        }
    }

    fn lastAttr(self: *const DOM, node_idx: u32) u32 {
        return switch (self.nodes.items[node_idx]) {
            .element => |e| e.last_attr,
            else => unreachable,
        };
    }

    fn attrName(self: *const DOM, attr_idx: u32) u32 {
        return switch (self.nodes.items[attr_idx]) { .attribute => |a| a.name, else => unreachable };
    }

    fn setAttrValue(self: *DOM, attr_idx: u32, value_id: u32) void {
        switch (self.nodes.items[attr_idx]) { .attribute => |*a| a.value = value_id, else => unreachable }
    }

    fn appendChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_idx = parent_id - 1;
        const child_idx = child_id - 1;

        self.setParent(child_idx, parent_id);
        self.setNext(child_idx, 0);

        if (self.firstChild(parent_idx) == 0) {
            self.setFirstChild(parent_idx, child_id);
            self.setLastChild(parent_idx, child_id);
        } else {
            const last_idx = self.lastChild(parent_idx) - 1;
            self.setNext(last_idx, child_id);
            self.setLastChild(parent_idx, child_id);
        }
    }

    fn prependChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_idx = parent_id - 1;
        const child_idx = child_id - 1;

        const old_first = self.firstChild(parent_idx);
        self.setParent(child_idx, parent_id);
        self.setNext(child_idx, old_first);
        self.setFirstChild(parent_idx, child_id);
        if (old_first == 0) self.setLastChild(parent_idx, child_id);
    }

    fn removeChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == 0 or child_id == 0 or parent_id > self.nodes.items.len or child_id > self.nodes.items.len)
            return error.InvalidNodeIndex;

        const parent_idx = parent_id - 1;

        var current = self.firstChild(parent_idx);
        var prev: u32 = 0;
        while (current != 0) {
            if (current == child_id) {
                const current_idx = current - 1;
                const next = self.getNext(current_idx);

                if (prev == 0) {
                    self.setFirstChild(parent_idx, next);
                } else {
                    self.setNext(prev - 1, next);
                }

                if (self.lastChild(parent_idx) == child_id)
                    self.setLastChild(parent_idx, prev);

                self.setParent(current_idx, 0);
                self.setNext(current_idx, 0);
                return;
            }
            prev = current;
            current = self.getNext(current - 1);
        }
        return error.ChildNotFound;
    }

    fn setAttribute(self: *DOM, element_id: u32, name_id: u32, value_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len) return error.InvalidNodeIndex;
        const element_idx = element_id - 1;

        var current = self.firstAttr(element_idx);
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            if (self.attrName(attr_idx) == name_id) {
                self.setAttrValue(attr_idx, value_id);
                return;
            }
            prev = current;
            current = self.getNext(attr_idx);
        }

        const new_id: u32 = @intCast(self.nodes.items.len + 1);
        try self.createNodeAt(new_id, NodeData{ .attribute = .{ .name = name_id, .value = value_id, .parent = element_id } });

        if (self.firstAttr(element_idx) == 0) {
            self.setFirstAttr(element_idx, new_id);
            self.setLastAttr(element_idx, new_id);
        } else {
            const last_idx = self.lastAttr(element_idx) - 1;
            self.setNext(last_idx, new_id);
            self.setLastAttr(element_idx, new_id);
        }
    }

    fn removeAttribute(self: *DOM, element_id: u32, name_id: u32) !void {
        if (element_id == 0 or element_id > self.nodes.items.len) return error.InvalidNodeIndex;
        const element_idx = element_id - 1;

        var current = self.firstAttr(element_idx);
        var prev: u32 = 0;
        while (current != 0) {
            const attr_idx = current - 1;
            if (self.attrName(attr_idx) == name_id) {
                const next = self.getNext(attr_idx);
                if (prev == 0) self.setFirstAttr(element_idx, next) else self.setNext(prev - 1, next);
                if (self.lastAttr(element_idx) == current) self.setLastAttr(element_idx, prev);
                self.setParent(attr_idx, 0);
                self.setNext(attr_idx, 0);
                return;
            }
            prev = current;
            current = self.getNext(attr_idx);
        }
    }
};

pub const Builder = struct {
    strings: StringPool,
    next_node_id: u32,
    allocator: Allocator,
    actions: ArrayList(Action),

    pub fn init(allocator: Allocator) !Builder {
        var res = Builder{
            .allocator = allocator,
            .strings = StringPool.init(allocator),
            .next_node_id = 1,
            .actions = ArrayList(Action).init(allocator),
        };
        const empty = try allocator.dupe(u8, "");
        try res.strings.strings.append(empty);
        return res;
    }

    pub fn fromDom(dom: *const DOM, allocator: Allocator) !Builder {
        var b = Builder{
            .allocator = allocator,
            .strings = StringPool.init(allocator),
            .next_node_id = @intCast(dom.nodes.items.len + 1),
            .actions = ArrayList(Action).init(allocator),
        };
        // copy strings
        for (dom.strings.strings.items) |s| {
            const dup = try allocator.dupe(u8, s);
            try b.strings.strings.append(dup);
        }
        var it = dom.strings.map.iterator();
        while (it.next()) |entry| {
            const new_s = b.strings.strings.items[entry.value_ptr.*];
            try b.strings.map.put(new_s, entry.value_ptr.*);
        }
        return b;
    }

    pub fn deinit(self: *Builder) void {
        self.actions.deinit();
        self.strings.deinit();
    }

    pub fn createDocument(self: *Builder) !u32 {
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateDocument = .{ .node_id = node_id } });
        return node_id;
    }

    pub fn createElement(self: *Builder, tag_name: []const u8) !u32 {
        const tag_id = try self.strings.intern(tag_name);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateElement = .{ .node_id = node_id, .tag_name = tag_id } });
        return node_id;
    }

    pub fn createAttribute(self: *Builder, name: []const u8, value: []const u8) !u32 {
        const name_id = try self.strings.intern(name);
        const value_id = try self.strings.intern(value);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateAttribute = .{ .node_id = node_id, .name = name_id, .value = value_id } });
        return node_id;
    }

    pub fn createText(self: *Builder, text: []const u8) !u32 {
        const text_id = try self.strings.intern(text);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateText = .{ .node_id = node_id, .content = text_id } });
        return node_id;
    }

    pub fn createCDATA(self: *Builder, data: []const u8) !u32 {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateCDATA = .{ .node_id = node_id, .content = data_id } });
        return node_id;
    }

    pub fn createProcessingInstruction(self: *Builder, target: []const u8, data: []const u8) !u32 {
        const target_id = try self.strings.intern(target);
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateProcessingInstruction = .{ .node_id = node_id, .target = target_id, .content = data_id } });
        return node_id;
    }

    pub fn createComment(self: *Builder, data: []const u8) !u32 {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_node_id; self.next_node_id += 1;
        try self.actions.append(.{ .CreateComment = .{ .node_id = node_id, .content = data_id } });
        return node_id;
    }

    pub fn appendChild(self: *Builder, parent: u32, child: u32) !void {
        try self.actions.append(.{ .AppendChild = .{ .parent = parent, .child = child } });
    }

    pub fn prependChild(self: *Builder, parent: u32, child: u32) !void {
        try self.actions.append(.{ .PrependChild = .{ .parent = parent, .child = child } });
    }

    pub fn removeChild(self: *Builder, parent: u32, child: u32) !void {
        try self.actions.append(.{ .RemoveChild = .{ .parent = parent, .child = child } });
    }

    pub fn setAttribute(self: *Builder, element: u32, name: []const u8, value: []const u8) !void {
        const name_id = try self.strings.intern(name);
        const value_id = try self.strings.intern(value);
        try self.actions.append(.{ .SetAttribute = .{ .element = element, .name = name_id, .value = value_id } });
    }

    pub fn removeAttribute(self: *Builder, element: u32, name: []const u8) !void {
        const name_id = try self.strings.intern(name);
        try self.actions.append(.{ .RemoveAttribute = .{ .element = element, .name = name_id } });
    }

    pub fn buildDom(self: *Builder, base: *const DOM, allocator: Allocator) !DOM {
        var dom = try base.cloneWithBuilderStrings(allocator, &self.strings);
        for (self.actions.items) |a| {
            try a.apply(&dom);
        }
        return dom;
    }
};

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

const CreateDocumentAction = struct { node_id: u32 };
const CreateElementAction = struct { node_id: u32, tag_name: u32 };
const CreateAttributeAction = struct { node_id: u32, name: u32, value: u32 };
const CreateTextAction = struct { node_id: u32, content: u32 };
const CreateCDATASectionAction = struct { node_id: u32, content: u32 };
const CreateProcessingInstructionAction = struct { node_id: u32, target: u32, content: u32 };
const CreateCommentAction = struct { node_id: u32, content: u32 };
const AppendChildAction = struct { parent: u32, child: u32 };
const PrependChildAction = struct { parent: u32, child: u32 };
const RemoveChildAction = struct { parent: u32, child: u32 };
const SetAttributeAction = struct { element: u32, name: u32, value: u32 };
const RemoveAttributeAction = struct { element: u32, name: u32 };

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
            .CreateDocument => |a| try dom.createNodeAt(a.node_id, NodeData{ .document = .{} }),
            .CreateElement => |a| try dom.createNodeAt(a.node_id, NodeData{ .element = .{ .tag_name = a.tag_name } }),
            .CreateAttribute => |a| try dom.createNodeAt(a.node_id, NodeData{ .attribute = .{ .name = a.name, .value = a.value } }),
            .CreateText => |a| try dom.createNodeAt(a.node_id, NodeData{ .text = .{ .content = a.content } }),
            .CreateCDATA => |a| try dom.createNodeAt(a.node_id, NodeData{ .cdata = .{ .content = a.content } }),
            .CreateProcessingInstruction => |a| try dom.createNodeAt(a.node_id, NodeData{ .proc_inst = .{ .content = a.content } }),
            .CreateComment => |a| try dom.createNodeAt(a.node_id, NodeData{ .comment = .{ .content = a.content } }),
            .AppendChild => |a| try dom.appendChild(a.parent, a.child),
            .PrependChild => |a| try dom.prependChild(a.parent, a.child),
            .RemoveChild => |a| try dom.removeChild(a.parent, a.child),
            .SetAttribute => |a| try dom.setAttribute(a.element, a.name, a.value),
            .RemoveAttribute => |a| try dom.removeAttribute(a.element, a.name),
        }
    }
};

const Node = struct {
    dom: *const DOM,
    id: u32,

    inline fn nodeData(self: Node) NodeData { return self.dom.nodes.items[self.id - 1]; }

    pub fn nodeType(self: Node) NodeType { return std.meta.activeTag(self.nodeData()); }

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
        const sibling_id = self.dom.getNext(self.id - 1);
        if (sibling_id == 0) return null;
        return Node{ .dom = self.dom, .id = sibling_id };
    }

    pub fn childNodes(self: Node) NodeList { return NodeList{ .dom = self.dom, .parent_id = self.id }; }

    pub fn getTagName(self: Node) ?u32 { return switch (self.nodeData()) { .element => |e| e.tag_name, else => null }; }

    pub fn getAttrName(self: Node) ?u32 { return switch (self.nodeData()) { .attribute => |a| a.name, else => null }; }

    pub fn getAttrValue(self: Node) ?u32 { return switch (self.nodeData()) { .attribute => |a| a.value, else => null }; }

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

const NodeList = struct {
    dom: *const DOM,
    parent_id: u32,

    pub fn length(self: NodeList) u32 {
        var count: u32 = 0;
        var current = self.dom.firstChild(self.parent_id - 1);
        while (current != 0) : (current = self.dom.getNext(current - 1)) count += 1;
        return count;
    }

    pub fn item(self: NodeList, index: u32) ?Node {
        var current = self.dom.firstChild(self.parent_id - 1);
        var i: u32 = 0;
        while (current != 0) : (current = self.dom.getNext(current - 1)) {
            if (i == index) return Node{ .dom = self.dom, .id = current };
            i += 1;
        }
        return null;
    }
};

const NamedNodeMap = struct {
    world: *const DOM,
    element_id: u32,

    inline fn first_attr(self: NamedNodeMap) u32 { return switch (self.world.nodes.items[self.element_id - 1]) { .element => |e| e.first_attr, else => unreachable }; }

    pub fn length(self: NamedNodeMap) u32 {
        var count: u32 = 0;
        var current = self.first_attr();
        while (current != 0) : (current = self.world.getNext(current - 1)) count += 1;
        return count;
    }

    pub fn item(self: NamedNodeMap, index: u32) ?Node {
        var current = self.first_attr();
        var i: u32 = 0;
        while (current != 0) {
            if (i == index) return Node{ .dom = self.world, .id = current };
            i += 1;
            current = self.world.getNext(current - 1);
        }
        return null;
    }

    pub fn getNamedItem(self: NamedNodeMap, name: []const u8) ?Node {
        var current = self.first_attr();
        while (current != 0) {
            const attr_idx = current - 1;
            const attr_name_id = switch (self.world.nodes.items[attr_idx]) { .attribute => |a| a.name, else => 0 };
            const attr_name = self.world.strings.getString(attr_name_id);
            if (std.mem.eql(u8, attr_name, name)) return Node{ .dom = self.world, .id = current };
            current = switch (self.world.nodes.items[attr_idx]) { .attribute => |a| a.next, else => 0 };
        }
        return null;
    }
};

test "append doc with elem" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    try builder.appendChild(doc, elem);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    if (dom2.nodes.items.len >= doc) {
        const n = dom2.nodes.items[doc - 1];
        try testing.expect(std.meta.activeTag(n) == .document);
        try testing.expect(switch (n) { .document => |d| d.first_child, else => undefined } == elem);
    }

    const elem_node = Node{ .dom = &dom2, .id = elem };
    try testing.expect(elem_node.nodeType() == .element);
    try testing.expect(elem_node.parentNode().?.id == doc);
    try testing.expectEqualStrings("div", dom2.strings.getString(elem_node.getTagName().?));
}

test "append doc with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const text = try builder.createText("Hello World");
    try builder.appendChild(doc, text);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    const doc_node = dom2.nodes.items[doc - 1];
    try testing.expect(std.meta.activeTag(doc_node) == .document);
    try testing.expect(switch (doc_node) { .document => |d| d.first_child, else => undefined } == text);

    const text_node_wrapper = Node{ .dom = &dom2, .id = text };
    try testing.expect(text_node_wrapper.nodeType() == .text);
    try testing.expect(text_node_wrapper.parentNode().?.id == doc);
    try testing.expectEqualStrings("Hello World", dom2.strings.getString(text_node_wrapper.getTextContent().?));
}

test "prepend doc with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    const text = try builder.createText("Hello");

    try builder.appendChild(doc, elem);
    try builder.prependChild(doc, text);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    const doc_node = dom2.nodes.items[doc - 1];
    try testing.expect(switch (doc_node) { .document => |d| d.first_child, else => undefined } == text);

    const text_node_wrapper = Node{ .dom = &dom2, .id = text };
    try testing.expect(switch (dom2.nodes.items[text - 1]) { .text => |t| t.next, else => undefined } == elem);
    try testing.expectEqualStrings("Hello", dom2.strings.getString(text_node_wrapper.getTextContent().?));
}

test "append elem with elem" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const parent = try builder.createElement("div");
    const child = try builder.createElement("span");

    try builder.appendChild(doc, parent);
    try builder.appendChild(parent, child);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    const parent_node_wrapper = Node{ .dom = &dom2, .id = parent };
    const child_node_wrapper = Node{ .dom = &dom2, .id = child };

    try testing.expect(switch (dom2.nodes.items[parent - 1]) { .element => |e| e.first_child, else => undefined } == child);
    try testing.expect(child_node_wrapper.parentNode().?.id == parent);
    try testing.expectEqualStrings("div", dom2.strings.getString(parent_node_wrapper.getTagName().?));
    try testing.expectEqualStrings("span", dom2.strings.getString(child_node_wrapper.getTagName().?));
}

test "append elem with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("p");
    const text = try builder.createText("Content");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    _ = Node{ .dom = &dom2, .id = elem };
    const text_node_wrapper = Node{ .dom = &dom2, .id = text };

    try testing.expect(switch (dom2.nodes.items[elem - 1]) { .element => |e| e.first_child, else => undefined } == text);
    try testing.expect(text_node_wrapper.parentNode().?.id == elem);
    try testing.expectEqualStrings("Content", dom2.strings.getString(text_node_wrapper.getTextContent().?));
}

test "prepend elem with elem" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const parent = try builder.createElement("ul");
    const child1 = try builder.createElement("li");
    const child2 = try builder.createElement("li");

    try builder.appendChild(doc, parent);
    try builder.appendChild(parent, child1);
    try builder.prependChild(parent, child2);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    _ = Node{ .dom = &dom2, .id = parent };
    try testing.expect(switch (dom2.nodes.items[parent - 1]) { .element => |e| e.first_child, else => undefined } == child2);

    const child2_node_wrapper = Node{ .dom = &dom2, .id = child2 };
    try testing.expect(switch (dom2.nodes.items[child2 - 1]) { .element => |e| e.next, else => undefined } == child1);
    try testing.expect(child2_node_wrapper.parentNode().?.id == parent);
}

test "prepend elem with text" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("h1");
    const text1 = try builder.createText("World");
    const text2 = try builder.createText("Hello ");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text1);
    try builder.prependChild(elem, text2);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    _ = Node{ .dom = &dom2, .id = elem };
    try testing.expect(switch (dom2.nodes.items[elem - 1]) { .element => |e| e.first_child, else => undefined } == text2);

    const text2_node_wrapper = Node{ .dom = &dom2, .id = text2 };
    const text1_node_wrapper = Node{ .dom = &dom2, .id = text1 };
    try testing.expect(switch (dom2.nodes.items[text2 - 1]) { .text => |t| t.next, else => undefined } == text1);
    try testing.expectEqualStrings("Hello ", dom2.strings.getString(text2_node_wrapper.getTextContent().?));
    try testing.expectEqualStrings("World", dom2.strings.getString(text1_node_wrapper.getTextContent().?));
}

test "set attribute on element" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");

    try builder.appendChild(doc, elem);
    try builder.setAttribute(elem, "class", "container");

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    _ = Node{ .dom = &dom2, .id = elem };
    const first_attr = switch (dom2.nodes.items[elem - 1]) { .element => |e| e.first_attr, else => undefined };
    try testing.expect(first_attr != 0);

    const attr_id = first_attr;
    const attr_node_wrapper = Node{ .dom = &dom2, .id = attr_id };
    try testing.expect(attr_node_wrapper.nodeType() == .attribute);
    try testing.expectEqualStrings("class", dom2.strings.getString(attr_node_wrapper.getAttrName().?));
    try testing.expectEqualStrings("container", dom2.strings.getString(attr_node_wrapper.getAttrValue().?));
}

test "remove child" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    const text = try builder.createText("Hello");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text);
    try builder.removeChild(elem, text);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    _ = Node{ .dom = &dom2, .id = elem };
    try testing.expect(switch (dom2.nodes.items[elem - 1]) { .element => |e| e.first_child, else => undefined } == 0);
    try testing.expect(switch (dom2.nodes.items[elem - 1]) { .element => |e| e.last_child, else => undefined } == 0);

    _ = Node{ .dom = &dom2, .id = text };
    try testing.expect(switch (dom2.nodes.items[text - 1]) { .text => |t| t.parent, else => undefined } == 0);
}

test "nodelist" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    const text1 = try builder.createText("Hello");
    const text2 = try builder.createText("World");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text1);
    try builder.appendChild(elem, text2);

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    const elem_node_wrapper = Node{ .dom = &dom2, .id = elem };
    const nodes = elem_node_wrapper.childNodes();
    try testing.expect(nodes.length() == 2);
    try testing.expect(nodes.item(0).?.id == text1);
    try testing.expect(nodes.item(1).?.id == text2);
}

test "namednodemap" {
    var dom1 = try DOM.init(testing.allocator);
    defer dom1.deinit();

    var builder = try Builder.fromDom(&dom1, testing.allocator);
    defer builder.deinit();

    _ = try builder.createDocument();
    const elem = try builder.createElement("div");
    try builder.setAttribute(elem, "class", "container");
    try builder.setAttribute(elem, "id", "main");

    var dom2 = try builder.buildDom(&dom1, testing.allocator);
    defer dom2.deinit();

    const attr_map = NamedNodeMap{ .world = &dom2, .element_id = elem };
    try testing.expect(attr_map.length() == 2);
    const class_attr = attr_map.getNamedItem("class").?;
    try testing.expectEqualStrings("container", dom2.strings.getString(class_attr.getAttrValue().?));
    const id_attr = attr_map.getNamedItem("id").?;
    try testing.expectEqualStrings("main", dom2.strings.getString(id_attr.getAttrValue().?));
}
