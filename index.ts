import { dlopen, FFIType, suffix, CString, Pointer } from 'bun:ffi';
const { i32, u8, ptr, cstring, uint64_t: usize } = FFIType;

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  doc_init: { args: [cstring, usize], returns: ptr },
  elem_init: { args: [cstring, usize], returns: ptr },
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: u8 },
  tag_name: { args: [ptr], returns: cstring },
  attr_init: { args: [cstring, usize, cstring, usize], returns: ptr },
  attr_name: { args: [ptr], returns: cstring },
  attr_val: { args: [ptr], returns: cstring },
  attr_set: { args: [ptr, cstring, usize], returns: i32 },
  // Element related functions for Attribute
  attr_get: { args: [ptr, cstring, usize], returns: ptr },
  attr_add: { args: [ptr, cstring, usize, cstring, usize], returns: ptr },
  attr_del: { args: [ptr, cstring, usize], returns: i32 },
  // Parser functions
  parse: { args: [cstring, usize], returns: ptr },
});

export enum NodeType {
  ELEMENT_NODE = 1,
  ATTRIBUTE_NODE = 2,
  TEXT_NODE = 3,
  CDATA_SECTION_NODE = 4,
  PROCESSING_INSTRUCTION_NODE = 7,
  COMMENT_NODE = 8,
  DOCUMENT_NODE = 9,
  DOCUMENT_TYPE_NODE = 10,
  DOCUMENT_FRAGMENT_NODE = 11,
}

export abstract class Node {
  protected readonly ptr: Pointer;

  constructor(ptr: Pointer) {
    this.ptr = ptr;
  }

  get nodeType(): NodeType {
    return symbols.node_type(this.ptr) as NodeType;
  }
}

class Document extends Node {
  constructor() {
    super(symbols.doc_init()!);
  }
}

export class Element extends Node {
  constructor(tagName: string) {
    const s = Buffer.from(tagName);
    super(symbols.elem_init(s, s.byteLength)!);
  }

  get tagName(): string {
    return symbols.tag_name(this.ptr).toString();
  }

  get prefix(): string | null {
    return null;
  }

  getAttribute(name: string): string | null {
    const attr = symbols.attr_get(this.ptr, Buffer.from(name), name.length);
    if (attr === null) return null;
    return symbols.attr_val(attr).toString();
  }

  getAttributeNode(): Node | null {
    throw 'not implemented';
  }

  setAttribute(name: string, value: string): void {
    symbols.attr_set(this.ptr, Buffer.from(name), name.length, Buffer.from(value), value.length);
  }

  setAttributeNode(node: Node): void {
    throw 'not implemented';
  }

  hasAttribute(name: string): boolean {
    return false;
  }
}

class Attr extends Node {
  get name(): string | null {
    return symbols.attr_name(this.ptr).toString();
  }

  get localName(): string | null {
    return null;
  }

  get prefix(): string | null {
    return null;
  }

  get value(): string {
    return symbols.attr_val(this.ptr).toString();
  }

  get ownerElement(): Element | null {
    return null;
  }

  get namespaceURI(): string | null {
    return '';
  }
}

abstract class CharacterData extends Node {
  abstract data: string;
  abstract readonly length: number;
  abstract readonly nextElementSibling: Element | null;
  abstract readonly previousElementSibling: Element | null;
}

class Text extends CharacterData {
  data: string = '';
  get length(): number {
    return this.data.length;
  }
  get nextElementSibling(): Element | null {
    return null;
  }
  get previousElementSibling(): Element | null {
    return null;
  }
}

class ProcessingInstruction extends CharacterData {
  data: string = '';
  get length(): number {
    return this.data.length;
  }
  get nextElementSibling(): Element | null {
    return null;
  }
  get previousElementSibling(): Element | null {
    return null;
  }

  get target(): string {
    return 'todo';
  }
}

class CDATASection extends CharacterData {
  data: string = '';
  get length(): number {
    return this.data.length;
  }
  get nextElementSibling(): Element | null {
    return null;
  }
  get previousElementSibling(): Element | null {
    return null;
  }
}

class Comment extends CharacterData {
  data: string = '';
  get length(): number {
    return this.data.length;
  }
  get nextElementSibling(): Element | null {
    return null;
  }
  get previousElementSibling(): Element | null {
    return null;
  }
}

const nodeTypes = {
  1: Element,
  2: Attr,
  3: Text,
  7: ProcessingInstruction,
  8: Comment,
  9: Document,
} as const;

export function parseXML(xml: string): Node | null {
  const buf = Buffer.from(xml);
  const nodePtr = symbols.parse(buf, buf.length);
  if (nodePtr === null) return null;

  const nodeType = symbols.node_type(nodePtr) as NodeType;
  const NodeClass = (nodeTypes as any)[nodeType];
  if (!NodeClass) {
    symbols.node_free(nodePtr);
    return null;
  }

  return new NodeClass(nodePtr);
}

// Example usage
const doc = new Document();
console.log("doc", doc.nodeType);

const elem = new Element("div");
console.log('type', elem.nodeType);
console.log('name', elem.tagName);

console.log('attr id', elem.getAttribute('id'));
elem.setAttribute("id", "1");
console.log('attr id', elem.getAttribute('id'));

// Test parser
const xml = `
<?xml version="1.0" encoding="UTF-8"?>
<root id="1">
  <child class="test">Hello, <b>World</b>!</child>
</root>
`;
const parsedNode = parseXML(xml);
console.log('parsed node type', parsedNode?.nodeType);
