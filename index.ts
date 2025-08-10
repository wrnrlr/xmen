// JavaScript implementation of XMEN FFI
import { dlopen, FFIType, suffix, CString, Pointer } from 'bun:ffi';
const { i32, u8, ptr, cstring, i64 } = FFIType;

console.log(`./zig-out/lib/libxmen.${suffix}`)

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  // Constructors
  alloc_elem: { args: [cstring], returns: ptr },
  alloc_attr: { args: [cstring, cstring], returns: ptr },
  alloc_text: { args: [cstring], returns: ptr },
  alloc_cdata: { args: [cstring], returns: ptr },
  alloc_comment: { args: [cstring], returns: ptr },
  alloc_procinst: { args: [cstring], returns: ptr },
  alloc_doc: { args: [], returns: ptr },

  // General Node properties
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: u8 },
  node_parent: { args: [ptr], returns: ptr },
  node_set_parent: { args: [ptr, ptr], returns: i32 },

  // Inner node: Element & Document
  inode_children: { args: [ptr], returns: ptr },
  inode_count: { args: [ptr], returns: i64 },
  inode_append: { args: [ptr, ptr], returns: i32 },
  inode_prepend: { args: [ptr, ptr], returns: i32 },

  // Element
  elem_tag: { args: [ptr], returns: cstring },
  elem_attrs: { args: [ptr], returns: ptr },
  elem_attr: { args: [ptr, cstring], returns: cstring },
  elem_set_attr: { args: [ptr, cstring, cstring], returns: i32 },
  elem_remove_attr: { args: [ptr, cstring], returns: i32 },

  // Attribute
  attr_name: { args: [ptr], returns: cstring },
  attr_value: { args: [ptr], returns: cstring },
  attr_set_value: { args: [ptr, cstring], returns: i32 },

  // Text Comment CData ProcInst
  content_get: { args: [ptr], returns: cstring },
  content_set: { args: [ptr, cstring], returns: i32 },

  // NamedNodeMap
  map_length: { args: [ptr], returns: i32 },
  // map_item: { args: [ptr, i32], returns: ptr }, // What does this?
  map_get: { args: [ptr, cstring], returns: ptr },
  map_set: { args: [ptr, ptr], returns: i32 },
  map_remove: { args: [ptr, cstring], returns: i32 },

  // NodeList
  list_length: { args: [ptr], returns: i32 },
  list_item: { args: [ptr, i32], returns: ptr },
  list_append: { args: [ptr, ptr], returns: i32 },
  list_prepend: { args: [ptr, ptr], returns: i32 },

  // SAX
  sax_alloc: {},
  sax_cb: {},
  sax_write: {},
  sax_free: {},

  // XMLParser
  xml_parse: { args: [cstring], returns: ptr },

  //
  xpath_eval: { args: [cstring, ptr], returns: ptr },
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

  get parentNode(): Node | null {
    const parentPtr = symbols.node_parent(this.ptr);
    if (!parentPtr) return null;
    return createNode(parentPtr);
  }

  appendChild(child: Node): void {
    symbols.inode_append(this.ptr, child.ptr);
  }

  prependChild(child: Node): void {
    symbols.inode_prepend(this.ptr, child.ptr);
  }

  // Manual free to avoid memory leaks
  free(): void {
    symbols.node_free(this.ptr);
  }
}

export class Document extends Node {
  constructor() {
    super(symbols.alloc_doc()!);
  }
}

export class Element extends Node {
  constructor(tagNameOrPtr: string | Pointer) {
    if (typeof tagNameOrPtr === 'string') {
      super(symbols.alloc_elem(tagNameOrPtr)!);
    } else {
      super(tagNameOrPtr);
    }
  }

  get tagName(): string {
    return symbols.elem_tag(this.ptr)?.toString() ?? '';
  }

  get prefix(): string | null {
    return null; // No namespace support
  }

  getAttribute(name: string): string | null {
    return symbols.elem_get_attr(this.ptr, name)?.toString() ?? null;
  }

  getAttributeNode(name: string): Attr | null {
    const attrPtr = symbols.map_get(symbols.elem_attrs(this.ptr), name);
    if (!attrPtr) return null;
    return new Attr(attrPtr);
  }

  setAttribute(name: string, value: string): void {
    symbols.elem_set_attr(this.ptr, name, value);
  }

  setAttributeNode(node: Attr): void {
    symbols.map_set(symbols.elem_attrs(this.ptr), node.ptr);
  }

  hasAttribute(name: string): boolean {
    return !!symbols.elem_get_attr(this.ptr, name);
  }

  removeAttribute(name: string): void {
    symbols.elem_remove_attr(this.ptr, name);
  }
}

export class Attr extends Node {
  constructor(nameOrPtr: string | Pointer, value?: string) {
    if (typeof nameOrPtr === 'string') {
      if (value === undefined) throw new Error('Value required for new Attr');
      super(symbols.alloc_attr(nameOrPtr, value)!);
    } else {
      super(nameOrPtr);
    }
  }

  get name(): string {
    return symbols.attr_name(this.ptr)?.toString() ?? '';
  }

  get localName(): string | null {
    return this.name; // No namespace
  }

  get prefix(): string | null {
    return null;
  }

  get value(): string {
    return symbols.attr_value(this.ptr)?.toString() ?? '';
  }

  set value(val: string) {
    symbols.attr_set_value(this.ptr, val);
  }

  get ownerElement(): Element | null {
    const parentPtr = symbols.node_parent(this.ptr);
    if (!parentPtr) return null;
    return new Element(parentPtr);
  }

  get namespaceURI(): string | null {
    return null;
  }
}

export abstract class CharacterData extends Node {
  get data(): string {
    return symbols.content_get(this.ptr)?.toString() ?? '';
  }

  set data(value: string) {
    symbols.content_set(this.ptr, value);
  }

  get nextElementSibling(): Element | null {
    return null; // TODO: Implement if needed
  }

  get previousElementSibling(): Element | null {
    return null; // TODO: Implement if needed
  }

  get length(): number {
    return this.data.length;
  }
}

export class Text extends CharacterData {
  constructor(contentOrPtr: string | Pointer) {
    if (typeof contentOrPtr === 'string') {
      super(symbols.alloc_text(contentOrPtr)!);
    } else {
      super(contentOrPtr);
    }
  }
}

export class ProcessingInstruction extends CharacterData {
  constructor(contentOrPtr: string | Pointer) {
    if (typeof contentOrPtr === 'string') {
      super(symbols.alloc_procinst(contentOrPtr)!);
    } else {
      super(contentOrPtr);
    }
  }

  get target(): string {
    const content = this.data;
    const spaceIndex = content.indexOf(' ');
    return spaceIndex !== -1 ? content.slice(0, spaceIndex) : content;
  }
}

export class CDATASection extends CharacterData {
  constructor(contentOrPtr: string | Pointer) {
    if (typeof contentOrPtr === 'string') {
      super(symbols.alloc_cdata(contentOrPtr)!);
    } else {
      super(contentOrPtr);
    }
  }
}

export class Comment extends CharacterData {
  constructor(contentOrPtr: string | Pointer) {
    if (typeof contentOrPtr === 'string') {
      super(symbols.alloc_comment(contentOrPtr)!);
    } else {
      super(contentOrPtr);
    }
  }
}

const nodeTypes: { [key: number]: new (ptr: Pointer) => Node } = {
  1: Element,
  2: Attr,
  3: Text,
  7: ProcessingInstruction,
  8: Comment,
  9: Document,
} as const;

function createNode(ptr: Pointer): Node {
  const type = symbols.node_type(ptr);
  const Cls = nodeTypes[type] || Node;
  return new Cls(ptr);
}

// Example usage:
const doc = new Document();
const elem = new Element('div');
elem.setAttribute('id', 'main');
const text = new Text('Hello, world!');
elem.appendChild(text);
doc.appendChild(elem);

// To free resources when done
text.free();
elem.free();
doc.free();
