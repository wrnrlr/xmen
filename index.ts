import { dlopen, FFIType, suffix, CString, Pointer } from 'bun:ffi';
const { i32, u8, ptr, function: callback, cstring, uint64_t:usize } = FFIType;

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  doc_init: { args: [cstring, usize], returns: ptr },
  elem_init: { args: [cstring, usize], returns: ptr },
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: u8 },
  tag_name: { args: [ptr], returns: cstring },
  attr_init: { args: [cstring, usize, cstring, usize], returns: ptr },
  attr_get: { args: [ptr, cstring, usize], returns: ptr },
  attr_set: { args: [ptr, cstring, usize, cstring, usize], returns: ptr },
  attr_has: { args: [ptr, cstring, usize], returns: i32 },
  attr_del: { args: [ptr, cstring, usize], returns: i32 },
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
  protected readonly ptr: Pointer

  constructor(ptr: Pointer) {
    this.ptr = ptr
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
    const s = Buffer.from(tagName)
    super(symbols.elem_init(s, s.byteLength)!);
  }

  // The tagName read-only property of the Element interface returns the tag name of the element on which it's called.
  get tagName(): string {
    return symbols.tag_name(this.ptr).toString();
  }

  //The prefix read-only property returns the namespace prefix of the specified element, or null if no prefix is specified.
  get prefix(): string|null { return null }

  getAttribute(name: string): string|null {
    const attr = symbols.attr_get(this.ptr, Buffer.from(name), name.length)
    if (attr === null) return null
    console.log('attr', attr)
    return attr.toString()
  }

  setAttribute(name: string, value: string): void {
    symbols.attr_set(this.ptr, Buffer.from(name), name.length, Buffer.from(value), value.length);
  }

  hasAttribute(name: string): boolean {
    return symbols.attr_has(this.ptr, Buffer.from(name), name.length) !== 0;
  }
}

class Attr extends Node {

  // The attribute's qualified name. If the attribute is not in a namespace, it will be the same as localName property.
  get name(): string|null { return null }

  // A string representing the local part of the qualified name of the attribute.
  get localName(): string|null { return null }

  // The read-only prefix property of the Attr returns the namespace prefix of the attribute, or null if no prefix is specified.
  get prefix(): string|null { return null }

  // The value property of the Attr interface contains the value of the attribute.
  get value(): string { return '' }

  // The read-only ownerElement property of the Attr interface returns the Element the attribute belongs to.
  get ownerElement(): Element|null { return null }

  // The read-only namespaceURI property of the Attr interface returns the namespace URI of the attribute, or null if the element is not in a namespace.
  get namespaceURI(): string|null { return '' }
}

abstract class CharacterData extends Node {
  // A string representing the textual data contained in this object.
  abstract data: string

  // Returns a number representing the size of the string contained in the object.
  abstract readonly length: number

  // Returns the first Element that follows this node, and is a sibling, or null if this is the last.
  abstract readonly nextElementSibling: Element|null

  // Returns the first Element that precedes this node, and is a sibling, or null if this is the first.
  abstract readonly previousElementSibling: Element|null
}

class Text extends CharacterData {
  data: string = ''
  get length(): number { return this.data.length }
  get nextElementSibling(): Element|null { return null }
  get previousElementSibling(): Element|null { return null }
}

class ProcessingInstruction extends CharacterData {
  data: string = ''
  get length(): number { return this.data.length }
  get nextElementSibling(): Element|null { return null }
  get previousElementSibling(): Element|null { return null }

  // The read-only target property of the ProcessingInstruction interface represent the application to which the ProcessingInstruction is targeted.
  get target(): string { return 'todo' }
}

class CDATASection extends CharacterData {
  data: string = ''
  get length(): number { return this.data.length }
  get nextElementSibling(): Element|null { return null }
  get previousElementSibling(): Element|null { return null }
}

class Comment extends CharacterData {
  data: string = ''
  get length(): number { return this.data.length }
  get nextElementSibling(): Element|null { return null }
  get previousElementSibling(): Element|null { return null }
}

const nodeTypes = {
  1: Element,
  2: Attr,
  3: Text,
  // 4: 'CDATA_SECTION_NODE',
  // 7: 'PROCESSING_INSTRUCTION_NODE',
  // 8: 'COMMENT_NODE',
  9: Document,
  // 10: 'DOCUMENT_TYPE_NODE:',
  // 11: 'DOCUMENT_FRAGMENT_NODE:',
} as const


const doc = new Document()
console.log("doc", doc.nodeType)

const elem = new Element("div")
console.log('type', elem.nodeType)
console.log('name', elem.tagName)

console.log('attr id', elem.getAttribute('id'))
elem.setAttribute("id", "1")
console.log('attr id', elem.getAttribute('id'))
