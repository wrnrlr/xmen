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
import { parse, xpath, sax } from './index.ts';

const xml = `
<root>
  <child attr="a">A</child>
  <child attr="b">b</child>
</root>
`;

// Parse XML document from string
const doc = parse(xml);

// Select element in XML document
const nodes = xpath('/root/child[@attr="A"]', doc)
for (const node of nodes) console.log(node.toJSON())

// Test SAX parsing
const resp = await fetch('')
const events:any = sax(resp.stream)
for await (const event of events) console.log(event.toJSON())
```

## Proposed CLI

```bash
$ xmen xpath -f <URL|FILE|DIR> /library/book
```

## TODO

* Maybe use [SegmentedList](https://ziglang.org/documentation/master/std/#std.segmented_list.SegmentedList) for `NodeList`.


##

## Awesome Links
* [Invisible XML](https://invisiblexml.org/)
* [SaxonJS](https://www.saxonica.com/saxonjs/documentation2/index.html)
* [XQuery and XPath Data Model 4.0](https://qt4cg.org/specifications/xpath-datamodel-40/Overview.html)
* [XQuery 4.0](https://qt4cg.org/specifications/xquery-40/xquery-40.html#id-introduction)
* XSD 1.1
* iXML
* Metainf
