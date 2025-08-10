import { dlopen, FFIType, suffix, CString, Pointer } from 'bun:ffi';
const { i32, u8, ptr, cstring, uint64_t: usize } = FFIType;

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  // Constructors
  alloc_elem: { args: [cstring, usize], returns: ptr },
  alloc_attr: { args: [cstring, usize], returns: ptr },
  alloc_text: { args: [cstring, usize], returns: ptr },
  alloc_cdata: { args: [cstring, usize], returns: ptr },
  alloc_comment: { args: [cstring, usize], returns: ptr },
  alloc_procinst: { args: [cstring, usize], returns: ptr },
  alloc_doc: { args: [cstring, usize], returns: ptr },

  // General Node properties
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: u8 },
  node_parent: { args: [ptr], returns: ptr },
  node_setParent: { args: [ptr, ptr], returns: i32 },

  // Inner node: Element & Document
  inode_children: { args: [ptr], returns: ptr },
  inode_count: { args: [ptr], returns: ptr },
  inode_append: { args: [ptr, ptr] },
  inode_prepend: { args: [ptr, ptr] },

  // Element
  elem_tag: { args: [ptr], returns: cstring },
  elem_attributes: { args: [ptr] },
  elem_getAttributes: { args: [ptr] },
  elem_setAttributes: { args: [ptr] },
  elem_removeAttributes: { args: [ptr] },

  // Attribute
  attr_name: { args: [ptr] },
  attr_value: { args: [ptr] },
  attr_getValue: { args: [ptr] },

  // Text Comment CData ProcInst
  char_content: { args: [ptr] },
  char_setContent: {},

  // NamedNodeMap
  map_get: { args: [ptr], returns: ptr },
  map_set: { args: [ptr] },
  map_remove: { args: [ptr] },

  // NodeList
  list_length: { args: [ptr], returns: i32 },
  list_index: { args: [ptr, i32], returns: ptr },
  list_append: { args: [ptr, ptr] },
  list_prepend: { args: [ptr, ptr] },

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
  public readonly ptr: Pointer;

  constructor(ptr: Pointer) {
    this.ptr = ptr;
  }

  get nodeType(): NodeType {
    return symbols.node_type(this.ptr) as NodeType;
  }
}

class Document extends Node {
  constructor() {
    super(symbols.alloc_doc()!)
  }
}

export class Element extends Node {
  constructor(tagName: string) {
    super(symbols.alloc_elem(tagName)!)
  }

  get tagName(): string {
    return symbols.elem_tag(this.ptr).toString();
  }

  get prefix(): string | null {
    return null;
  }

  getAttribute(name: string): string | null {
    throw 'TODO'
  }

  getAttributeNode(): Node | null {
    throw 'TODO'
  }

  setAttribute(name: string, value: string): void {
    throw 'TODO'
  }

  setAttributeNode(node: Node): void {
    throw 'TODO'
  }

  hasAttribute(name: string): boolean {
    throw 'TODO'
  }
}

class Attr extends Node {
  constructor(name: string, value: string) {
    super(symbols.alloc_attr(name, value)!)
  }

  get name(): string | null {
    throw 'TODO'
  }

  get localName(): string | null {
    throw 'TODO'
  }

  get prefix(): string | null {
    throw 'TODO'
  }

  get value(): string {
    throw 'TODO'
  }

  get ownerElement(): Element | null {
    throw 'TODO'
  }

  get namespaceURI(): string | null {
    throw 'TODO'
  }
}

abstract class CharacterData extends Node {
  data: string = '';
  get nextElementSibling(): Element | null {
    return null;
  }
  get previousElementSibling(): Element | null {
    return null;
  }
  get length(): number {
    return this.data.length;
  }
}

class Text extends CharacterData {
  constructor(content: string) {
    super(symbols.alloc_attr()!)
  }
}

class ProcessingInstruction extends CharacterData {
  constructor(content: string) {
    super(symbols.alloc_attr(content)!)
  }

  get target(): string {
    return 'todo';
  }
}

class CDATASection extends CharacterData {
  constructor(content: string) {
    super(symbols.alloc_cdata(content)!)
  }
}

class Comment extends CharacterData {
  constructor(content: string) {
    super(symbols.alloc_comment(content)!)
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

function createElement(tagName: string): Element {
  throw 'todo';
}

// Parser

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

// XPath

function xpath(xpath: string, node: Node): Node | null {
  const buf = Buffer.from(xpath);
  const ptr = symbols.xpath_eval(buf, buf.length, node.ptr);
  if (ptr === null) return null;

  const nodeType = symbols.node_type(ptr) as NodeType;
  return symbols.node_type(ptr) === 1 ? new Element(ptr) : new Document(ptr)
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

// Test XPath
const xpathResult = parsedNode?.evaluateXPath("/root/child[@class=\"test\"]");
console.log('xpath result type', xpathResult?.nodeType);
