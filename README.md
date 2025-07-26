# XMEN: XML Enterprise

## Get started

## JavaScript API

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

## CLI

```bash
$ xmen xpath -f <URL|FILE|DIR> /library/book
```

## TODO
* SAX Parsing Implementation: The sax.zig file is a minimal implementation. You'll need to replace the feed method with your actual SAX parsing logic, ensuring it emits SaxEvent instances with null-terminated strings ([*c]const u8) and properly manages memory.

* Memory Management: The sax.zig code frees strings in the feed method. If the JavaScript side needs to retain strings, modify saxParse in index.ts to call symbols.free_string for each [*c]const u8 field (e.g., event.start_element!.name).

* Error Handling: Add error checking in index.ts for FFI calls (e.g., check if symbols.parse returns null). Example:javascript

export function parse(xml: string): XMLDocument {
  const docPtr = symbols.parse(xml);
  if (!docPtr) throw new Error('Failed to parse XML');
  return new XMLDocument(docPtr);
}

* Platform Compatibility: The fixes are tailored for aarch64_aapcs_darwin but should work on other platforms. Test on x86_64 or Windows if needed.
Attributes Iteration: The Element.attributes() generator in index.ts is a placeholder. To support it, add a Zig function like node_attributes to iterate over attributes, similar to node_children.

## Status

* XML 1.1
* XSD 1.1
* XPath 3.1
* [XQuery 4.0](https://qt4cg.org/specifications/xquery-40/xquery-40.html#id-introduction)
* iXML
* Metainf

## Awesome Links
* [Invisible XML](https://invisiblexml.org/)
* [SaxonJS](https://www.saxonica.com/saxonjs/documentation2/index.html)
* [XQuery and XPath Data Model 4.0](https://qt4cg.org/specifications/xpath-datamodel-40/Overview.html)
