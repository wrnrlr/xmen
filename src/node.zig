const std = @import("std");
const dom = @import("cow.zig");
const DOM = dom.DOM;
const None = dom.None;
const NodeType = dom.NodeType;
const Builder = dom.Builder;

const Node = struct {
    dom: *const DOM,
    id: u32,

    pub fn nodeType(self: Node) NodeType { return self.dom.nodeType(self.id); }

    pub fn parentNode(self: Node) ?Node {
        const parent_id = self.dom.parent(self.id);
        if (parent_id == None) return null;
        return Node{ .dom = self.dom, .id = parent_id };
    }

    fn createNode(self: Node, id: u32) ?Node {
        const child_id = self.dom.firstChild(id);
        if (child_id == None) return null;
        return Node{ .dom = self.dom, .id = id };
    }

    pub fn firstChild(self: Node) ?Node {
        return switch (self.nodeType()) {
            .document, .element => self.createNode(self.dom.firstChild(self.id)),
            else => null,
        };
    }

    pub fn lastChild(self: Node) ?Node {
        return switch (self.nodeType()) {
            .document, .element => self.createNode(self.dom.lastChild(self.id)),
            else => null,
        };
    }

    pub fn nextSibling(self: Node) ?Node {
        return self.createNode(self.dom.nextSibling(self.id));
    }

    pub fn prevSibling(self: Node) ?Node {
        return self.createNode(self.dom.prevSibling(self.id));
    }

    pub fn childNodes(self: Node) NodeList { return NodeList{ .dom = self.dom, .parent_id = self.id }; }

    pub fn getTagName(self: Node) ?u32 {
        if (self.nodeType() != .element) return null;
        return self.dom.tagName(self.id);
    }

    pub fn getAttrName(self: Node) ?u32 {
        if (self.nodeType() != .attribute) return null;
        return self.dom.attrName(self.id);
    }

    pub fn getAttrValue(self: Node) ?u32 {
        if (self.nodeType() != .attribute) return null;
        return self.dom.attrValue(self.id);
    }

    pub fn getTextContent(self: Node) ?u32 {
        return switch (self.nodeType()) {
            .text => self.dom.textContent(self.id),
            .cdata => self.dom.cdataContent(self.id),
            .proc_inst => self.dom.procInstContent(self.id),
            .comment => self.dom.commentContent(self.id),
            else => null,
        };
    }
};

const NodeList = struct {
    dom: *const DOM,
    parent_id: u32,

    pub fn length(self: NodeList) u32 {
        var count: u32 = 0;
        var current = self.dom.firstChild(self.parent_id);
        while (current != None) : (current = self.dom.next(current)) count += 1;
        return count;
    }

    pub fn item(self: NodeList, index: u32) ?Node {
        var current = self.dom.firstChild(self.parent_id);
        var i: u32 = 0;
        while (current != None) : (current = self.dom.next(current)) {
            if (i == index) return Node{ .dom = self.dom, .id = current };
            i += 1;
        }
        return null;
    }
};

const NamedNodeMap = struct {
    world: *const DOM,
    element_id: u32,

    inline fn first_attr(self: NamedNodeMap) u32 { return switch (self.world.nodes.items[self.element_id]) { .element => |e| e.first_attr, else => unreachable }; }

    pub fn length(self: NamedNodeMap) u32 {
        var count: u32 = 0;
        var current = self.first_attr();
        while (current != None) : (current = self.world.next(current)) count += 1;
        return count;
    }

    pub fn item(self: NamedNodeMap, index: u32) ?Node {
        var current = self.first_attr();
        var i: u32 = 0;
        while (current != None) {
            if (i == index) return Node{ .dom = self.world, .id = current };
            i += 1;
            current = self.world.next(current);
        }
        return null;
    }

    pub fn getNamedItem(self: NamedNodeMap, name: []const u8) ?Node {
        var current = self.first_attr();
        while (current != None) {
            const attr_name_id = switch (self.world.nodes.items[current]) { .attribute => |a| a.name, else => unreachable };
            const attr_name = self.world.strings.getString(attr_name_id);
            if (std.mem.eql(u8, attr_name, name)) return Node{ .dom = self.world, .id = current };
            current = switch (self.world.nodes.items[current]) { .attribute => |a| a.next, else => unreachable };
        }
        return null;
    }
};

const testing = std.testing;

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

    try testing.expect(dom2.firstChild(elem) == text1);
    try testing.expect(dom2.nextSibling(text1) == text2);
    try testing.expect(dom2.nextSibling(text2) == None);
    try testing.expect(dom2.lastChild(elem) == text2);
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

    const first_attr = dom2.firstAttr(elem);
    try testing.expect(first_attr != None);
    try testing.expect(dom2.nodeType(first_attr) == .attribute);
    try testing.expectEqualStrings("class", dom2.strings.getString(dom2.attrName(first_attr)));
    try testing.expectEqualStrings("container", dom2.strings.getString(dom2.attrValue(first_attr)));

    const second_attr = dom2.nextSibling(first_attr);
    try testing.expect(second_attr != None);
    try testing.expect(dom2.nodeType(second_attr) == .attribute);
    try testing.expectEqualStrings("id", dom2.strings.getString(dom2.attrName(second_attr)));
    try testing.expectEqualStrings("main", dom2.strings.getString(dom2.attrValue(second_attr)));

    try testing.expect(dom2.nextSibling(second_attr) == None);
}
