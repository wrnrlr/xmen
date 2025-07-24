const std = @import("std");

const Allocator = std.mem.Allocator;

const TokenType = enum { Slash, Identifier, At, Equals, StringLiteral, LBracket, RBracket, EOF };
const Token = struct { type: TokenType, value: []const u8 };

const NodeType = enum { Element, Predicate };
pub const AstNode = struct {
    type: NodeType,
    name: ?[]const u8 = null,
    predicate: ?*AstNode = null,
    children: std.ArrayList(*AstNode),
    attribute: ?[]const u8 = null,
    value: ?[]const u8 = null,

    pub fn deinit(self: *AstNode, allocator: Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit();
        if (self.predicate) |pred| {
            pred.deinit(allocator);
            allocator.destroy(pred);
        }
        self.predicate = null;
    }
};

const Lexer = struct {
    input: []const u8,
    pos: usize,
    allocator: Allocator,

    fn init(input: []const u8, allocator: Allocator) Lexer {
        return Lexer{ .input = input, .pos = 0, .allocator = allocator };
    }

    fn nextToken(self: *Lexer) !Token {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
        if (self.pos >= self.input.len) return Token{ .type = .EOF, .value = "" };
        const c = self.input[self.pos];
        self.pos += 1;
        switch (c) {
            '/' => return Token{ .type = .Slash, .value = "/" },
            '@' => return Token{ .type = .At, .value = "@" },
            '=' => return Token{ .type = .Equals, .value = "=" },
            '[' => return Token{ .type = .LBracket, .value = "[" },
            ']' => return Token{ .type = .RBracket, .value = "]" },
            '"', '\'' => {
                const start = self.pos;
                while (self.pos < self.input.len and self.input[self.pos] != c) {
                    self.pos += 1;
                }
                if (self.pos >= self.input.len) return error.UnterminatedString;
                const value = self.input[start..self.pos];
                self.pos += 1;
                return Token{ .type = .StringLiteral, .value = value };
            },
            else => {
                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
                    const start = self.pos - 1;
                    while (self.pos < self.input.len and
                           (std.ascii.isAlphanumeric(self.input[self.pos]) or
                            self.input[self.pos] == '_' or
                            self.input[self.pos] == '-')) {
                        self.pos += 1;
                    }
                    return Token{ .type = .Identifier, .value = self.input[start..self.pos] };
                }
                return error.InvalidCharacter;
            },
        }
    }
};

pub const XPathParser = struct {
    lexer: ?Lexer = null, // Make lexer optional since it's set in parse
    current_token: ?Token = null, // Optional until parsing starts
    allocator: Allocator,

    pub fn init(allocator: Allocator) XPathParser {
        return XPathParser{
            .allocator = allocator,
        };
    }

    fn advance(self: *XPathParser) !void {
        if (self.lexer == null) return error.NoLexer;
        self.current_token = try self.lexer.?.nextToken();
    }

    fn expect(self: *XPathParser, token_type: TokenType) !void {
        if (self.current_token == null or self.current_token.?.type != token_type) {
            return error.UnexpectedToken;
        }
        try self.advance();
    }

    pub fn parse(self: *XPathParser, input: []const u8) !*AstNode {
        // Initialize lexer with input
        self.lexer = Lexer.init(input, self.allocator);
        self.current_token = try self.lexer.?.nextToken();

        if (self.current_token.?.type != .Slash) {
            return error.ExpectedSlash;
        }
        try self.advance();
        return try self.parsePath();
    }

    fn parsePath(self: *XPathParser) !*AstNode {
        const node = try self.allocator.create(AstNode);
        errdefer {
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        node.* = AstNode{
            .type = .Element,
            .name = null,
            .predicate = null,
            .children = std.ArrayList(*AstNode).init(self.allocator),
            .attribute = null,
            .value = null,
        };

        if (self.current_token == null or self.current_token.?.type != .Identifier) {
            return error.ExpectedIdentifier;
        }
        node.name = self.current_token.?.value;
        try self.advance();

        if (self.current_token != null and self.current_token.?.type == .LBracket) {
            node.predicate = try self.parsePredicate();
        }

        if (self.current_token != null and self.current_token.?.type == .Slash) {
            try self.advance();
            const child = try self.parsePath();
            try node.children.append(child);
        }

        return node;
    }

    fn parsePredicate(self: *XPathParser) !*AstNode {
        try self.expect(.LBracket);
        const node = try self.allocator.create(AstNode);
        errdefer {
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        node.* = AstNode{
            .type = .Predicate,
            .name = null,
            .predicate = null,
            .children = std.ArrayList(*AstNode).init(self.allocator),
            .attribute = null,
            .value = null,
        };

        if (self.current_token == null or self.current_token.?.type != .At) {
            return error.ExpectedAt;
        }
        try self.advance();

        if (self.current_token == null or self.current_token.?.type != .Identifier) {
            return error.ExpectedIdentifier;
        }
        node.attribute = self.current_token.?.value;
        try self.advance();

        try self.expect(.Equals);

        if (self.current_token == null or self.current_token.?.type != .StringLiteral) {
            return error.ExpectedStringLiteral;
        }
        node.value = self.current_token.?.value;
        try self.advance();

        try self.expect(.RBracket);
        return node;
    }
};

fn printAst(node: *AstNode, indent: usize) void {
    const spaces = "  " ** 32;
    std.debug.print("{s}", .{spaces[0..indent * 2]});
    switch (node.type) {
        .Element => {
            std.debug.print("/{s}\n", .{node.name orelse "unnamed"});
            if (node.predicate) |pred| printAst(pred, indent + 1);
            for (node.children.items) |child| printAst(child, indent + 1);
        },
        .Predicate => {
            std.debug.print("@{s}=\"{s}\"\n", .{node.attribute orelse "", node.value orelse ""});
        },
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const xpath = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator); // No input here
    const ast = try parser.parse(xpath); // Pass input to parse
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }
    printAst(ast, 0);
}

const testing = std.testing;

test "Lexer: basic tokenization" {
    const allocator = testing.allocator;
    const input = "/root/child[@attr=\"value\"]/grandchild";
    var lexer = Lexer.init(input, allocator);

    const expected_tokens = [_]struct { TokenType, []const u8 }{
        .{ .Slash, "/" },
        .{ .Identifier, "root" },
        .{ .Slash, "/" },
        .{ .Identifier, "child" },
        .{ .LBracket, "[" },
        .{ .At, "@" },
        .{ .Identifier, "attr" },
        .{ .Equals, "=" },
        .{ .StringLiteral, "value" },
        .{ .RBracket, "]" },
        .{ .Slash, "/" },
        .{ .Identifier, "grandchild" },
        .{ .EOF, "" },
    };

    for (expected_tokens) |expected| {
        const token = try lexer.nextToken();
        try testing.expectEqual(expected[0], token.type);
        try testing.expectEqualStrings(expected[1], token.value);
    }
}

test "Lexer: unterminated string error" {
    const allocator = testing.allocator;
    const input = "/root[@attr=\"unterminated";
    var lexer = Lexer.init(input, allocator);

    // Advance past valid tokens
    _ = try lexer.nextToken(); // Slash
    _ = try lexer.nextToken(); // Identifier
    _ = try lexer.nextToken(); // LBracket
    _ = try lexer.nextToken(); // At
    _ = try lexer.nextToken(); // Identifier
    _ = try lexer.nextToken(); // Equals

    try testing.expectError(error.UnterminatedString, lexer.nextToken());
}

test "Lexer: invalid character" {
    const allocator = testing.allocator;
    const input = "/root$child";
    var lexer = Lexer.init(input, allocator);

    // Advance past valid tokens
    _ = try lexer.nextToken(); // Slash
    _ = try lexer.nextToken(); // Identifier

    try testing.expectError(error.InvalidCharacter, lexer.nextToken());
}

test "Parser: simple path" {
    const allocator = testing.allocator;
    const input = "/root/child";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(input);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    try testing.expectEqual(NodeType.Element, ast.type);
    try testing.expectEqualStrings("root", ast.name orelse "");
    try testing.expectEqual(@as(usize, 1), ast.children.items.len);
    try testing.expectEqual(NodeType.Element, ast.children.items[0].type);
    try testing.expectEqualStrings("child", ast.children.items[0].name orelse "");
}

test "Parser: path with predicate" {
    const allocator = testing.allocator;
    const input = "/root/child[@attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(input);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    try testing.expectEqual(NodeType.Element, ast.type);
    try testing.expectEqualStrings("root", ast.name orelse "");
    try testing.expectEqual(@as(usize, 1), ast.children.items.len);

    const child = ast.children.items[0];
    try testing.expectEqual(NodeType.Element, child.type);
    try testing.expectEqualStrings("child", child.name orelse "");
    try testing.expect(child.predicate != null);

    const pred = child.predicate.?;
    try testing.expectEqual(NodeType.Predicate, pred.type);
    try testing.expectEqualStrings("attr", pred.attribute orelse "");
    try testing.expectEqualStrings("value", pred.value orelse "");
}

test "Parser: complex path" {
    const allocator = testing.allocator;
    const input = "/root/child[@attr=\"value\"]/grandchild";
    var parser = XPathParser.init(allocator);
    const ast = try parser.parse(input);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    try testing.expectEqual(NodeType.Element, ast.type);
    try testing.expectEqualStrings("root", ast.name orelse "");
    try testing.expectEqual(@as(usize, 1), ast.children.items.len);

    const child = ast.children.items[0];
    try testing.expectEqual(NodeType.Element, child.type);
    try testing.expectEqualStrings("child", child.name orelse "");
    try testing.expect(child.predicate != null);

    const pred = child.predicate.?;
    try testing.expectEqual(NodeType.Predicate, pred.type);
    try testing.expectEqualStrings("attr", pred.attribute orelse "");
    try testing.expectEqualStrings("value", pred.value orelse "");

    try testing.expectEqual(@as(usize, 1), child.children.items.len);
    const grandchild = child.children.items[0];
    try testing.expectEqual(NodeType.Element, grandchild.type);
    try testing.expectEqualStrings("grandchild", grandchild.name orelse "");
}

test "Parser: invalid path - no slash" {
    const allocator = testing.allocator;
    const input = "root/child";
    var parser = XPathParser.init(allocator);
    try testing.expectError(error.ExpectedSlash, parser.parse(input));
}

test "Parser: invalid predicate - missing at" {
    const allocator = testing.allocator;
    const input = "/root/child[attr=\"value\"]";
    var parser = XPathParser.init(allocator);
    try testing.expectError(error.ExpectedAt, parser.parse(input));
}

test "Parser: invalid predicate - missing identifier" {
    const allocator = testing.allocator;
    const input = "/root/child[@=\"value\"]";
    var parser = XPathParser.init(allocator);
    try testing.expectError(error.ExpectedIdentifier, parser.parse(input));
}

test "Parser: invalid predicate - missing string literal" {
    const allocator = testing.allocator;
    const input = "/root/child[@attr=child]";
    var parser = XPathParser.init(allocator);
    try testing.expectError(error.ExpectedStringLiteral, parser.parse(input));
}
