const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const None: u32 = std.math.maxInt(u32);
pub const Root: u32 = 0;

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
    parent: u32 = None,
    next: u32 = None,
    prev: u32 = None,
};

// const ProcInstData = struct {
//     target: u32,
//     content: u32,
//     parent: u32 = None,
//     next: u32 = None,
//     prev: u32 = None,
// };

const NodeData = union(NodeType) {
    element: struct {
        tag_name: u32,
        parent: u32 = None,
        first_child: u32 = None,
        last_child: u32 = None,
        next: u32 = None,
        prev: u32 = None,
        first_attr: u32 = None,
        last_attr: u32 = None,
    },
    attribute: struct {
        name: u32,
        value: u32,
        parent: u32 = None,
        next: u32 = None,
        prev: u32 = None,
    },
    text: TextData,
    cdata: TextData,
    proc_inst: TextData,
    comment: TextData,
    document: struct {
        first_child: u32 = None,
        last_child: u32 = None,
    },
};

pub const DOM = struct {
    nodes: ArrayList(NodeData),
    strings: StringPool,

    pub fn init(allocator: Allocator) DOM {
        return DOM{
            .nodes = ArrayList(NodeData).init(allocator),
            .strings = StringPool.init(allocator),
        };
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
        const dummy = NodeData{ .document = .{ .first_child = None, .last_child = None } };
        while (self.nodes.items.len < node_id + 1) {
            try self.nodes.append(dummy);
        }
        self.nodes.items[node_id] = node_data;
    }

    pub fn createElem(self: *DOM, node_id: u32, tag: u32) !void { try self.createNodeAt(node_id, .{ .element = .{ .tag_name = tag } }); }

    pub fn createAttr(self: *DOM, node_id: u32, name: u32, value: u32) !void { try self.createNodeAt(node_id, .{ .attribute = .{ .name = name, .value = value } }); }

    pub fn createText(self: *DOM, node_id: u32, content: u32) !void { try self.createNodeAt(node_id, .{ .text = .{ .content = content } }); }

    pub fn createComment(self: *DOM, node_id: u32, content: u32) !void { try self.createNodeAt(node_id, .{ .comment = .{ .content = content } }); }

    pub fn createCData(self: *DOM, node_id: u32, content: u32) !void { try self.createNodeAt(node_id, .{ .cdata = .{ .content = content } }); }

    pub fn createProcInst(self: *DOM, node_id: u32, content: u32) !void { try self.createNodeAt(node_id, .{ .proc_inst = .{ .content = content } }); }

    pub fn createDoc(self: *DOM, node_id: u32) !void { try self.createNodeAt(node_id, .{ .document = .{} }); }

    pub fn nodeType(self: *const DOM, node_id: u32) NodeType {
        return std.meta.activeTag(self.nodes.items[node_id]);
    }

    pub fn next(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .document => None,
            .element => |e| e.next,
            .attribute => |a| a.next,
            .text => |t| t.next,
            .cdata => |c| c.next,
            .proc_inst => |p| p.next,
            .comment => |co| co.next,
        };
    }

    pub fn setNext(self: *DOM, node_id: u32, val: u32) void {
        switch (self.nodes.items[node_id]) {
            .document => unreachable,
            .element => |*e| e.next = val,
            .attribute => |*a| a.next = val,
            .text => |*t| t.next = val,
            .cdata => |*c| c.next = val,
            .proc_inst => |*p| p.next = val,
            .comment => |*co| co.next = val,
        }
    }

    pub fn prev(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .document => None,
            .element => |e| e.prev,
            .attribute => |a| a.prev,
            .text => |t| t.prev,
            .cdata => |c| c.prev,
            .proc_inst => |p| p.prev,
            .comment => |co| co.prev,
        };
    }

    pub fn setPrev(self: *DOM, node_id: u32, val: u32) void {
        switch (self.nodes.items[node_id]) {
            .document => unreachable,
            .element => |*e| e.prev = val,
            .attribute => |*a| a.prev = val,
            .text => |*t| t.prev = val,
            .cdata => |*c| c.prev = val,
            .proc_inst => |*p| p.prev = val,
            .comment => |*co| co.prev = val,
        }
    }

    pub fn parent(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .document => None,
            .element => |e| e.parent,
            .attribute => |a| a.parent,
            .text => |t| t.parent,
            .cdata => |c| c.parent,
            .proc_inst => |p| p.parent,
            .comment => |co| co.parent,
        };
    }

    pub fn setParent(self: *DOM, node_id: u32, val: u32) void {
        switch (self.nodes.items[node_id]) {
            .document => unreachable,
            .element => |*e| e.parent = val,
            .attribute => |*a| a.parent = val,
            .text => |*t| t.parent = val,
            .cdata => |*c| c.parent = val,
            .proc_inst => |*p| p.parent = val,
            .comment => |*co| co.parent = val,
        }
    }

    pub fn firstChild(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.first_child,
            .document => |d| d.first_child,
            else => unreachable,
        };
    }

    pub fn setFirstChild(self: *DOM, node_id: u32, child_id: u32) void {
        switch (self.nodes.items[node_id]) {
            .element => |*e| e.first_child = child_id,
            .document => |*d| d.first_child = child_id,
            else => unreachable,
        }
    }

    pub fn lastChild(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.last_child,
            .document => |d| d.last_child,
            else => unreachable,
        };
    }

    pub fn setLastChild(self: *DOM, node_id: u32, child_id: u32) void {
        switch (self.nodes.items[node_id]) {
            .element => |*e| e.last_child = child_id,
            .document => |*d| d.last_child = child_id,
            else => unreachable,
        }
    }

    pub fn nextSibling(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.next,
            .text => |t| t.next,
            .attribute => |a| a.next,
            else => None,
        };
    }

    pub fn prevSibling(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.prev,
            .text => |t| t.prev,
            .attribute => |a| a.prev,
            else => None,
        };
    }

    pub fn tagName(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.tag_name,
            else => unreachable,
        };
    }

    pub fn textContent(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .text => |t| t.content,
            else => unreachable,
        };
    }

    pub fn firstAttr(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.first_attr,
            else => unreachable,
        };
    }

    pub fn setFirstAttr(self: *DOM, node_id: u32, attr_id: u32) void {
        switch (self.nodes.items[node_id]) {
            .element => |*e| e.first_attr = attr_id,
            else => unreachable,
        }
    }

    pub fn setLastAttr(self: *DOM, node_id: u32, attr_id: u32) void {
        switch (self.nodes.items[node_id]) {
            .element => |*e| e.last_attr = attr_id,
            else => unreachable,
        }
    }

    pub fn lastAttr(self: *const DOM, node_id: u32) u32 {
        return switch (self.nodes.items[node_id]) {
            .element => |e| e.last_attr,
            else => unreachable,
        };
    }

    pub fn attrName(self: *const DOM, attr_id: u32) u32 {
        return switch (self.nodes.items[attr_id]) { .attribute => |a| a.name, else => unreachable };
    }

    pub fn attrValue(self: *const DOM, attr_id: u32) u32 {
        return switch (self.nodes.items[attr_id]) { .attribute => |a| a.value, else => unreachable };
    }

    pub fn setAttrValue(self: *DOM, attr_id: u32, value_id: u32) void {
        switch (self.nodes.items[attr_id]) { .attribute => |*a| a.value = value_id, else => unreachable }
    }

    pub fn appendChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == None or child_id == None or parent_id >= self.nodes.items.len or child_id >= self.nodes.items.len)
            return error.InvalidNodeIndex;

        self.setParent(child_id, parent_id);
        self.setNext(child_id, None);
        const last_id = self.lastChild(parent_id);
        self.setPrev(child_id, last_id);

        if (self.firstChild(parent_id) == None) {
            self.setFirstChild(parent_id, child_id);
            self.setLastChild(parent_id, child_id);
        } else {
            self.setNext(last_id, child_id);
            self.setLastChild(parent_id, child_id);
        }
    }

    pub fn prependChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == None or child_id == None or parent_id >= self.nodes.items.len or child_id >= self.nodes.items.len)
            return error.InvalidNodeIndex;

        self.setParent(child_id, parent_id);
        const old_first = self.firstChild(parent_id);
        self.setNext(child_id, old_first);
        self.setPrev(child_id, None);
        self.setFirstChild(parent_id, child_id);
        if (old_first == None) {
            self.setLastChild(parent_id, child_id);
        } else {
            self.setPrev(old_first, child_id);
        }
    }

    pub fn removeChild(self: *DOM, parent_id: u32, child_id: u32) !void {
        if (parent_id == None or child_id == None or parent_id >= self.nodes.items.len or child_id >= self.nodes.items.len)
            return error.InvalidNodeIndex;

        if (self.parent(child_id) != parent_id) return error.ChildNotFound;

        const before = self.prev(child_id);
        const after = self.next(child_id);

        if (before != None) {
            self.setNext(before, after);
        } else {
            self.setFirstChild(parent_id, after);
        }

        if (after != None) {
            self.setPrev(after, before);
        } else {
            self.setLastChild(parent_id, before);
        }

        self.setParent(child_id, None);
        self.setNext(child_id, None);
        self.setPrev(child_id, None);
    }

    pub fn setAttribute(self: *DOM, element_id: u32, name_id: u32, value_id: u32) !void {
        if (element_id == None or element_id >= self.nodes.items.len) return error.InvalidNodeIndex;

        var current = self.firstAttr(element_id);
        while (current != None) {
            if (self.attrName(current) == name_id) {
                self.setAttrValue(current, value_id);
                return;
            }
            current = self.next(current);
        }

        const new_id: u32 = @intCast(self.nodes.items.len); // TODO check if this is ok to do.
        try self.createNodeAt(new_id, NodeData{ .attribute = .{ .name = name_id, .value = value_id, .parent = element_id } });

        if (self.firstAttr(element_id) == None) {
            self.setFirstAttr(element_id, new_id);
            self.setLastAttr(element_id, new_id);
        } else {
            const last_id = self.lastAttr(element_id);
            self.setNext(last_id, new_id);
            self.setPrev(new_id, last_id);
            self.setLastAttr(element_id, new_id);
        }
    }

    pub fn removeAttribute(self: *DOM, element_id: u32, name_id: u32) !void {
        if (element_id == None or element_id >= self.nodes.items.len) return error.InvalidNodeIndex;

        var current = self.firstAttr(element_id);
        var before: u32 = None;
        while (current != None) {
            if (self.attrName(current) == name_id) {
                const after = self.next(current);
                if (before == None) {
                    self.setFirstAttr(element_id, after);
                } else {
                    self.setNext(before, after);
                }

                if (self.lastAttr(element_id) == current) {
                    self.setLastAttr(element_id, before);
                } else if (after != None) {
                    self.setPrev(after, before);
                }

                self.setParent(current, None);
                self.setNext(current, None);
                self.setPrev(current, None);
                return;
            }
            before = current;
            current = self.next(current);
        }
    }
};

pub const Builder = struct {
    allocator: Allocator,
    strings: StringPool,
    actions: ArrayList(Action),
    next_id: u32 = 0,

    pub fn init(allocator: Allocator) !Builder {
        return Builder{
            .allocator = allocator,
            .strings = StringPool.init(allocator),
            .actions = ArrayList(Action).init(allocator),
        };
    }

    pub fn build(self: *Builder) !DOM {
        var empty_dom = DOM.init(self.allocator);
        var dom = try empty_dom.cloneWithBuilderStrings(self.allocator, &self.strings);
        empty_dom.deinit();

        for (self.actions.items) |a| {
            try a.apply(&dom);
        }
        return dom;
    }

    pub fn deinit(self: *Builder) void {
        self.actions.deinit();
        self.strings.deinit();
    }

    pub fn createDocument(self: *Builder) !u32 {
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateDocument = .{ .node_id = node_id } });
        return node_id;
    }

    pub fn createElement(self: *Builder, tag_name: []const u8) !u32 {
        const tag_id = try self.strings.intern(tag_name);
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateElement = .{ .node_id = node_id, .tag_name = tag_id } });
        return node_id;
    }

    pub fn createAttribute(self: *Builder, name: []const u8, value: []const u8) !u32 {
        const name_id = try self.strings.intern(name);
        const value_id = try self.strings.intern(value);
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateAttribute = .{ .node_id = node_id, .name = name_id, .value = value_id } });
        return node_id;
    }

    pub fn createText(self: *Builder, text: []const u8) !u32 {
        const text_id = try self.strings.intern(text);
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateText = .{ .node_id = node_id, .content = text_id } });
        return node_id;
    }

    pub fn createCDATA(self: *Builder, data: []const u8) !u32 {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateCDATA = .{ .node_id = node_id, .content = data_id } });
        return node_id;
    }

    pub fn createProcessingInstruction(self: *Builder, target: []const u8, data: []const u8) !u32 {
        const target_id = try self.strings.intern(target);
        const data_id = try self.strings.intern(data);
        const node_id = self.next_id; self.next_id += 1;
        try self.actions.append(.{ .CreateProcessingInstruction = .{ .node_id = node_id, .target = target_id, .content = data_id } });
        return node_id;
    }

    pub fn createComment(self: *Builder, data: []const u8) !u32 {
        const data_id = try self.strings.intern(data);
        const node_id = self.next_id; self.next_id += 1;
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
const CreateProcInstAction = struct { node_id: u32, target: u32, content: u32 };
const ChildAction = struct { parent: u32, child: u32 };
const SetAttributeAction = struct { element: u32, name: u32, value: u32 };
const RemoveAttributeAction = struct { element: u32, name: u32 };

const Action = union(ActionType) {
    CreateDocument: CreateDocumentAction,
    CreateElement: CreateElementAction,
    CreateAttribute: CreateAttributeAction,
    CreateText: CreateTextAction,
    CreateCDATA: CreateTextAction,
    CreateProcessingInstruction: CreateProcInstAction,
    CreateComment: CreateTextAction,
    AppendChild: ChildAction,
    PrependChild: ChildAction,
    RemoveChild: ChildAction,
    SetAttribute: SetAttributeAction,
    RemoveAttribute: RemoveAttributeAction,

    fn apply(self: Action, dom: *DOM) !void {
        switch (self) {
            .CreateDocument => |a| try dom.createDoc(a.node_id),
            .CreateElement => |a| try dom.createElem(a.node_id,  a.tag_name),
            .CreateAttribute => |a| try dom.createAttr(a.node_id, a.name,  a.value),
            .CreateText => |a| try dom.createText(a.node_id, a.content),
            .CreateCDATA => |a| try dom.createCData(a.node_id, a.content),
            .CreateProcessingInstruction => |a| try dom.createProcInst(a.node_id, a.content),
            .CreateComment => |a| try dom.createComment(a.node_id, a.content),
            .AppendChild => |a| try dom.appendChild(a.parent, a.child),
            .PrependChild => |a| try dom.prependChild(a.parent, a.child),
            .RemoveChild => |a| try dom.removeChild(a.parent, a.child),
            .SetAttribute => |a| try dom.setAttribute(a.element, a.name, a.value),
            .RemoveAttribute => |a| try dom.removeAttribute(a.element, a.name),
        }
    }
};

test "append doc with elem" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    try builder.appendChild(doc, elem);

    var dom = try builder.build();
    defer dom.deinit();

    try testing.expect(dom.nodeType(doc) == .document);
    try testing.expect(dom.firstChild(doc) == elem);
    try testing.expect(dom.nodeType(elem) == .element);
    try testing.expect(dom.parent(elem) == doc);
    try testing.expectEqualStrings("div", dom.strings.getString(dom.tagName(elem)));
}

test "append doc with text" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const text = try builder.createText("Hello World");
    try builder.appendChild(doc, text);

    var dom = try builder.build();
    defer dom.deinit();

    try testing.expect(dom.nodeType(doc) == .document);
    try testing.expect(dom.firstChild(doc) == text);
    try testing.expect(dom.nodeType(text) == .text);
    try testing.expect(dom.parent(text) == doc);
    try testing.expectEqualStrings("Hello World", dom.strings.getString(dom.textContent(text)));
}

test "prepend doc with text" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    const text = try builder.createText("Hello");

    try builder.appendChild(doc, elem);
    try builder.prependChild(doc, text);

    var dom = try builder.build();
    defer dom.deinit();

    try testing.expect(dom.firstChild(doc) == text);
    try testing.expect(dom.nextSibling(text) == elem);
    try testing.expectEqualStrings("Hello", dom.strings.getString(dom.textContent(text)));
}

test "append elem with elem" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const parent = try builder.createElement("div");
    const child = try builder.createElement("span");

    try builder.appendChild(doc, parent);
    try builder.appendChild(parent, child);

    var dom2 = try builder.build();
    defer dom2.deinit();

    try testing.expect(dom2.firstChild(parent) == child);
    try testing.expect(dom2.parent(child) == parent);
    try testing.expectEqualStrings("div", dom2.strings.getString(dom2.tagName(parent)));
    try testing.expectEqualStrings("span", dom2.strings.getString(dom2.tagName(child)));
}

test "append elem with text" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("p");
    const text = try builder.createText("Content");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text);

    var dom = try builder.build();
    defer dom.deinit();

    try testing.expect(dom.firstChild(elem) == text);
    try testing.expect(dom.parent(text) == elem);
    try testing.expectEqualStrings("Content", dom.strings.getString(dom.textContent(text)));
}

test "prepend elem with elem" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const parent = try builder.createElement("ul");
    const child1 = try builder.createElement("li");
    const child2 = try builder.createElement("li");

    try builder.appendChild(doc, parent);
    try builder.appendChild(parent, child1);
    try builder.prependChild(parent, child2);

    var dom2 = try builder.build();
    defer dom2.deinit();

    try testing.expect(dom2.firstChild(parent) == child2);
    try testing.expect(dom2.nextSibling(child2) == child1);
    try testing.expect(dom2.parent(child2) == parent);
}

test "prepend elem with text" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("h1");
    const text1 = try builder.createText("World");
    const text2 = try builder.createText("Hello ");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text1);
    try builder.prependChild(elem, text2);

    var dom = try builder.build();
    defer dom.deinit();

    try testing.expect(dom.firstChild(elem) == text2);
    try testing.expect(dom.nextSibling(text2) == text1);
    try testing.expectEqualStrings("Hello ", dom.strings.getString(dom.textContent(text2)));
    try testing.expectEqualStrings("World", dom.strings.getString(dom.textContent(text1)));
}

test "set attribute on element" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");

    try builder.appendChild(doc, elem);
    try builder.setAttribute(elem, "class", "container");

    var dom2 = try builder.build();
    defer dom2.deinit();

    const first_attr = dom2.firstAttr(elem);
    try testing.expect(first_attr != None);

    try testing.expect(dom2.nodeType(first_attr) == .attribute);
    try testing.expectEqualStrings("class", dom2.strings.getString(dom2.attrName(first_attr)));
    try testing.expectEqualStrings("container", dom2.strings.getString(dom2.attrValue(first_attr)));
}

test "remove child" {
    var builder = try Builder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.createDocument();
    const elem = try builder.createElement("div");
    const text = try builder.createText("Hello");

    try builder.appendChild(doc, elem);
    try builder.appendChild(elem, text);
    try builder.removeChild(elem, text);

    var dom2 = try builder.build();
    defer dom2.deinit();

    try testing.expect(dom2.firstChild(elem) == None);
    try testing.expect(dom2.lastChild(elem) == None);
    try testing.expect(dom2.parent(text) == None);
}
