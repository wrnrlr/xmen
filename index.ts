import { dlopen, FFIType, suffix, CString, Pointer } from 'bun:ffi';
const { i32, u8, ptr, function: callback, cstring, uint64_t:usize } = FFIType;

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  doc_init: { args: [cstring, usize], returns: ptr },
  elem_init: { args: [cstring, usize], returns: ptr },
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: u8 },
  tag_name: { args: [ptr], returns: cstring },
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

  get tagName(): string {
    return symbols.tag_name(this.ptr).toString();
  }
}

class Attr {}
class Text {}

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
