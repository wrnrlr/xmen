import { dlopen, FFIType, suffix, CString } from 'bun:ffi';
const { i32, ptr, function: callback, cstring } = FFIType;

const path = `./zig-out/lib/libxmen.${suffix}`;
const { symbols } = dlopen(path, {
  node_create: { args: [cstring], returns: ptr },
  node_free: { args: [ptr], returns: i32 },
  node_type: { args: [ptr], returns: i32 },
  node_name: { args: [ptr], returns: cstring },
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
  abstract get nodeType(): NodeType;
  abstract get nodeName(): string;
}

export class Element extends Node {
  private ptr: unknown;

  constructor() {
    super();
    this.ptr = symbols.node_create();
  }

  get nodeType(): NodeType {
    return symbols.node_type(this.ptr) as NodeType;
  }

  get nodeName(): string {
    const namePtr = symbols.node_name(this.ptr);
    const name = new CString(namePtr).toString();
    symbols.string_free(namePtr);
    return name;
  }

  free() {
    console.log('FREE')
  }
}

const elem = new Element()
console.log(elem.nodeType)
console.log(elem.nodeName)
