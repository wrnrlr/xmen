# XMEN: XML for the Entrerprise

A fast and efficient implemention of XML and related technologies in Zig with high-level APIs for both Python and JavaScript.

## Get Started

### NodeJS & BunJS

    npm i @wrnrlr/xmen
    bun i @wrnrlr/xmen
    deno i npm:@wrnrlr/xmen

The APIs are the same on BunJS as on NodeJS, however the BunJS version uses `bun:ffi`.

### Browser


### Python

    pip install

### Zig

    zig fetch git+https://github.com/wrnrlr/xmen

## Current Status

[x] XML 1.1
[x] SAX
[ ] XPath 3.1
    [x] Parser
    [ ] Evaluator
[ ] Namespaces & QName

## Developer Instructions

To build XMEN from source zig is required.

    zig test src/*.zig
    zig build


## Proposed JavaScript API

```typescript
import { parseXML, xpath, sax } from './index.ts';

const xml = `
<root>
  <child attr="a">A</child>
  <child attr="b">b</child>
</root>
`;

// Parse XML document from string
const doc = xml(xml);

// Select element in XML document
const nodes = xpath('/root/child[@attr="A"]', doc)
for (const node of nodes)
  console.log(node.toJSON())

// Test SAX parsing
for await (const event of sax(xml))
  console.log(event)
```

## Proposed CLI

```bash
$ xmen xpath -f <URL|FILE|DIR> /library/book
```

## TODO

* Maybe use [SegmentedList](https://ziglang.org/documentation/master/std/#std.segmented_list.SegmentedList) for `NodeList`.
* Investigate what [String interning](https://en.wikipedia.org/wiki/String_interning) would mean doe api design and what speed trade-offs are involved. .

## Issues

### Parent removal logic can misbehave

In Node.setParent:

    if (n.parent()) |ancestor| {
        switch (ancestor.*) {
            .element => |*e| e.children.remove(n),
            .document => |*d| d.children.remove(n),
            else => unreachable,
        }
    }

Problem: remove on a NodeList might fail silently or leave stale pointers if not found.

Suggestion: Either assert the removal was successful or handle the case where the child isn't found (especially for cyclic reference prevention).


### Dom improvements

Document ownership clearly: either setNamedItem takes ownership, or it copies the node. Make the contract explicit in the function comment.

For safety you could make setNamedItem set the caller's pointer to null (if you change the signature to accept * *Node), so it's obvious to the caller that the pointer was moved. But that’s an API change.

Add a debug-time assertion or helper to check for double-free in tests (e.g. only call defer attr.destroy() when you know you still own it).

### Sax: Performance Concerns

Inefficient String Operations

    zigself.tag_name = self.buffer[record_start..self.pos];

Problem: Creates new string slices frequently, which could be optimized.

Unnecessary Allocations
The attributes ArrayList is cleared but capacity is retained, which is good,
but there are other areas where temporary allocations could be reduced.

4. Add Configuration Options
zigpub const ParserOptions = struct {
    validate_utf8: bool = true,
    max_nesting_depth: usize = 1000,
    max_attribute_count: usize = 100,
};

5. Improve Performance

Use string interning for common tag names
Implement streaming support for large documents
Add bounds checking optimizations

6. Better Testing Structure
The current tests are good, but could be organized better:

Separate performance tests
Property-based testing for edge cases
Fuzzing integration

## TREE design

### Overview
* This project implements a persistent, array-backed DOM tree.
* Nodes are stored in flat arrays, each identified by a numeric index.
* Children are stored contiguously in a single children array, with each node pointing to a range.
* Attributes are stored in a separate flat array.
* Copy-on-Write (COW): Updates create new slices of the children array and new node records along the path to the root, enabling cheap snapshots and structural sharing.
* Stable snapshots: Documents are immutable; transformations produce a new document version without affecting the old.
* XPath/XQuery friendly: Optional preorder/subtree metadata can be maintained for fast range queries and descendant/ancestor checks.

### New Features
Attributes
Stored in attributes[] flat array as (name_id, value_id) pairs.
Each node’s attributes_range gives start+len in the attributes buffer.
Names and values are string-interned IDs.

- Preorder / Subtree Size
  - Each Node has:
    - preorder: DFS number of first visit.
    - subtree_size: total nodes in its subtree (including itself).
  - Used for fast XPath range-based descendant queries.
- Batched Transformations
  - Transformation collects multiple edits:
    - Replace children.
    - Set attribute.
    - Update text.
  - Applied in one pass to minimize intermediate copies.
- String Interning
  - All tag names, attribute names, and text content are stored in a StringInterner.

 A compaction routine to reserialize a snapshot into tight arrays?

## Awesome Links
* [Invisible XML](https://invisiblexml.org/)
* [SaxonJS](https://www.saxonica.com/saxonjs/documentation2/index.html)
* [XQuery and XPath Data Model 4.0](https://qt4cg.org/specifications/xpath-datamodel-40/Overview.html)
* [XQuery 4.0](https://qt4cg.org/specifications/xquery-40/xquery-40.html#id-introduction)
* XSD 1.1
* Metainf
