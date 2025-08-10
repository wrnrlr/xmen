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
  elem_attr: { args: [ptr, cstring], returns: cstring }, // Fixed: was elem_get_attr
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
  map_item: { args: [ptr, i32], returns: ptr },
  map_get: { args: [ptr, cstring], returns: ptr },
  map_set: { args: [ptr, ptr], returns: i32 },
  map_remove: { args: [ptr, cstring], returns: i32 },

  // NodeList
  list_length: { args: [ptr], returns: i32 },
  list_item: { args: [ptr, i32], returns: ptr },
  list_append: { args: [ptr, ptr], returns: i32 },
  list_prepend: { args: [ptr, ptr], returns: i32 },

  // SAX
  sax_alloc: { args: [ptr, ptr], returns: ptr },
  sax_cb: { args: [ptr, ptr], returns: i32 },
  sax_write: { args: [ptr, cstring, i32], returns: i32 },
  sax_free: { args: [ptr], returns: i32 },

  // XML Parsing
  xml_parse: { args: [cstring], returns: ptr },

  // XPath
  xpath_eval: { args: [cstring, ptr], returns: ptr },
  xpath_result_free: { args: [ptr], returns: i32 },
  xpath_result_length: { args: [ptr], returns: i32 },
  xpath_result_item: { args: [ptr, i32], returns: ptr },
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

// NodeList implementation
export class NodeList {
  public readonly ptr: Pointer;

  constructor(ptr: Pointer) {
    this.ptr = ptr;
  }

  get length(): number {
    return symbols.list_length(this.ptr);
  }

  item(index: number): Node | null {
    if (index < 0 || index >= this.length) return null;
    const nodePtr = symbols.list_item(this.ptr, index);
    if (!nodePtr) return null;
    return createNode(nodePtr);
  }

  // Iterator support
  *[Symbol.iterator](): Iterator<Node> {
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) yield node;
    }
  }

  // Array-like access
  forEach(callback: (node: Node, index: number) => void): void {
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) callback(node, i);
    }
  }

  map<T>(callback: (node: Node, index: number) => T): T[] {
    const result: T[] = [];
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) result.push(callback(node, i));
    }
    return result;
  }

  filter(callback: (node: Node, index: number) => boolean): Node[] {
    const result: Node[] = [];
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node && callback(node, i)) result.push(node);
    }
    return result;
  }

  append(node: Node): void {
    symbols.list_append(this.ptr, node.ptr);
  }

  prepend(node: Node): void {
    symbols.list_prepend(this.ptr, node.ptr);
  }

  // Convert to regular Array
  toArray(): Node[] {
    return Array.from(this);
  }
}

// NamedNodeMap implementation
export class NamedNodeMap {
  public readonly ptr: Pointer;

  constructor(ptr: Pointer) {
    this.ptr = ptr;
  }

  get length(): number {
    return symbols.map_length(this.ptr);
  }

  item(index: number): Attr | null {
    if (index < 0 || index >= this.length) return null;
    const attrPtr = symbols.map_item(this.ptr, index);
    if (!attrPtr) return null;
    return new Attr(attrPtr);
  }

  getNamedItem(name: string): Attr | null {
    const attrPtr = symbols.map_get(this.ptr, name);
    if (!attrPtr) return null;
    return new Attr(attrPtr);
  }

  setNamedItem(attr: Attr): void {
    symbols.map_set(this.ptr, attr.ptr);
  }

  removeNamedItem(name: string): void {
    symbols.map_remove(this.ptr, name);
  }

  // Iterator support
  *[Symbol.iterator](): Iterator<Attr> {
    for (let i = 0; i < this.length; i++) {
      const attr = this.item(i);
      if (attr) yield attr;
    }
  }

  // Helper methods
  has(name: string): boolean {
    return this.getNamedItem(name) !== null;
  }

  keys(): string[] {
    const result: string[] = [];
    for (const attr of this) {
      result.push(attr.name);
    }
    return result;
  }

  values(): Attr[] {
    return Array.from(this);
  }
}

// XPath Result wrapper
export class XPathResult {
  public readonly ptr: Pointer;
  private _freed: boolean = false;

  constructor(ptr: Pointer) {
    this.ptr = ptr;
  }

  get length(): number {
    if (this._freed) return 0;
    return symbols.xpath_result_length(this.ptr);
  }

  item(index: number): Node | null {
    if (this._freed || index < 0 || index >= this.length) return null;
    const nodePtr = symbols.xpath_result_item(this.ptr, index);
    if (!nodePtr) return null;
    return createNode(nodePtr);
  }

  // Iterator support
  *[Symbol.iterator](): Iterator<Node> {
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) yield node;
    }
  }

  // Array-like methods
  forEach(callback: (node: Node, index: number) => void): void {
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) callback(node, i);
    }
  }

  map<T>(callback: (node: Node, index: number) => T): T[] {
    const result: T[] = [];
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node) result.push(callback(node, i));
    }
    return result;
  }

  filter(callback: (node: Node, index: number) => boolean): Node[] {
    const result: Node[] = [];
    for (let i = 0; i < this.length; i++) {
      const node = this.item(i);
      if (node && callback(node, i)) result.push(node);
    }
    return result;
  }

  // Convert to regular Array
  toArray(): Node[] {
    return Array.from(this);
  }

  // Get first matching node
  get firstNode(): Node | null {
    return this.item(0);
  }

  // Check if any results
  get isEmpty(): boolean {
    return this.length === 0;
  }

  // Free the XPath result
  free(): void {
    if (!this._freed) {
      symbols.xpath_result_free(this.ptr);
      this._freed = true;
    }
  }
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

  get childNodes(): NodeList | null {
    if (this.nodeType !== NodeType.ELEMENT_NODE && this.nodeType !== NodeType.DOCUMENT_NODE) {
      return null;
    }
    const listPtr = symbols.inode_children(this.ptr);
    if (!listPtr) return null;
    return new NodeList(listPtr);
  }

  get hasChildNodes(): boolean {
    return this.childNodes !== null && this.childNodes.length > 0;
  }

  appendChild(child: Node): void {
    symbols.inode_append(this.ptr, child.ptr);
  }

  prependChild(child: Node): void {
    symbols.inode_prepend(this.ptr, child.ptr);
  }

  // XPath evaluation on this node
  selectNodes(xpath: string): XPathResult {
    const resultPtr = symbols.xpath_eval(xpath, this.ptr);
    if (!resultPtr) throw new Error('XPath evaluation failed');
    return new XPathResult(resultPtr);
  }

  // Convenience method to get first matching node
  selectSingleNode(xpath: string): Node | null {
    const result = this.selectNodes(xpath);
    const node = result.firstNode;
    result.free();
    return node;
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

  get documentElement(): Element | null {
    const children = this.childNodes;
    if (!children) return null;

    for (const child of children) {
      if (child.nodeType === NodeType.ELEMENT_NODE) {
        return child as Element;
      }
    }
    return null;
  }

  createElement(tagName: string): Element {
    return new Element(tagName);
  }

  createTextNode(data: string): Text {
    return new Text(data);
  }

  createComment(data: string): Comment {
    return new Comment(data);
  }

  createCDATASection(data: string): CDATASection {
    return new CDATASection(data);
  }

  createProcessingInstruction(target: string, data: string = ''): ProcessingInstruction {
    const content = data ? `${target} ${data}` : target;
    return new ProcessingInstruction(content);
  }

  createAttribute(name: string, value: string = ''): Attr {
    return new Attr(name, value);
  }

  // Parse XML string into this document
  static parse(xmlString: string): Document | null {
    const docPtr = symbols.xml_parse(xmlString);
    if (!docPtr) return null;
    return new Document() // Note: This creates a new doc, you might need to adjust based on xml_parse implementation
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

  get localName(): string {
    const tagName = this.tagName;
    const colonIndex = tagName.indexOf(':');
    return colonIndex !== -1 ? tagName.slice(colonIndex + 1) : tagName;
  }

  get prefix(): string | null {
    const tagName = this.tagName;
    const colonIndex = tagName.indexOf(':');
    return colonIndex !== -1 ? tagName.slice(0, colonIndex) : null;
  }

  get attributes(): NamedNodeMap {
    const attrsPtr = symbols.elem_attrs(this.ptr);
    if (!attrsPtr) throw new Error('Failed to get attributes');
    return new NamedNodeMap(attrsPtr);
  }

  getAttribute(name: string): string | null {
    return symbols.elem_attr(this.ptr, name)?.toString() ?? null; // Fixed: was elem_get_attr
  }

  getAttributeNode(name: string): Attr | null {
    return this.attributes.getNamedItem(name);
  }

  setAttribute(name: string, value: string): void {
    symbols.elem_set_attr(this.ptr, name, value);
  }

  setAttributeNode(node: Attr): void {
    this.attributes.setNamedItem(node);
  }

  hasAttribute(name: string): boolean {
    return this.getAttribute(name) !== null;
  }

  removeAttribute(name: string): void {
    symbols.elem_remove_attr(this.ptr, name);
  }

  removeAttributeNode(node: Attr): void {
    this.attributes.removeNamedItem(node.name);
  }

  // Convenience methods for common operations
  get textContent(): string {
    let content = '';
    const children = this.childNodes;
    if (children) {
      for (const child of children) {
        if (child.nodeType === NodeType.TEXT_NODE ||
            child.nodeType === NodeType.CDATA_SECTION_NODE) {
          content += (child as CharacterData).data;
        } else if (child.nodeType === NodeType.ELEMENT_NODE) {
          content += (child as Element).textContent;
        }
      }
    }
    return content;
  }

  set textContent(value: string) {
    // Clear existing children and add new text node
    const children = this.childNodes;
    if (children) {
      // Note: This is a simplified implementation
      // In a real implementation, you'd need to remove all children first
    }
    const textNode = new Text(value);
    this.appendChild(textNode);
  }

  // Get elements by tag name
  getElementsByTagName(tagName: string): Element[] {
    const xpath = tagName === '*' ? './/*' : `.//${tagName}`;
    const result = this.selectNodes(xpath);
    const elements = result.filter((node): node is Element =>
      node.nodeType === NodeType.ELEMENT_NODE
    ) as Element[];
    result.free();
    return elements;
  }

  // Get element by ID (searches descendants)
  getElementById(id: string): Element | null {
    const xpath = `.//*[@id="${id}"]`;
    const result = this.selectNodes(xpath);
    const element = result.firstNode as Element | null;
    result.free();
    return element;
  }

  // Query selector using XPath
  querySelector(xpath: string): Element | null {
    const result = this.selectNodes(xpath);
    const element = result.firstNode as Element | null;
    result.free();
    return element;
  }

  querySelectorAll(xpath: string): Element[] {
    const result = this.selectNodes(xpath);
    const elements = result.filter((node): node is Element =>
      node.nodeType === NodeType.ELEMENT_NODE
    ) as Element[];
    result.free();
    return elements;
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

  get localName(): string {
    const name = this.name;
    const colonIndex = name.indexOf(':');
    return colonIndex !== -1 ? name.slice(colonIndex + 1) : name;
  }

  get prefix(): string | null {
    const name = this.name;
    const colonIndex = name.indexOf(':');
    return colonIndex !== -1 ? name.slice(0, colonIndex) : null;
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
    return null; // No namespace support yet
  }

  get specified(): boolean {
    return true; // All attributes are considered specified
  }
}

export abstract class CharacterData extends Node {
  get data(): string {
    return symbols.content_get(this.ptr)?.toString() ?? '';
  }

  set data(value: string) {
    symbols.content_set(this.ptr, value);
  }

  get textContent(): string {
    return this.data;
  }

  set textContent(value: string) {
    this.data = value;
  }

  get nextElementSibling(): Element | null {
    // TODO: Implement if needed
    return null;
  }

  get previousElementSibling(): Element | null {
    // TODO: Implement if needed
    return null;
  }

  get length(): number {
    return this.data.length;
  }

  substring(offset: number, count?: number): string {
    const data = this.data;
    if (count === undefined) {
      return data.slice(offset);
    }
    return data.slice(offset, offset + count);
  }

  appendData(data: string): void {
    this.data += data;
  }

  insertData(offset: number, data: string): void {
    const current = this.data;
    this.data = current.slice(0, offset) + data + current.slice(offset);
  }

  deleteData(offset: number, count: number): void {
    const current = this.data;
    this.data = current.slice(0, offset) + current.slice(offset + count);
  }

  replaceData(offset: number, count: number, data: string): void {
    const current = this.data;
    this.data = current.slice(0, offset) + data + current.slice(offset + count);
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

  splitText(offset: number): Text {
    const currentData = this.data;
    const newData = currentData.slice(offset);
    this.data = currentData.slice(0, offset);
    return new Text(newData);
  }

  get wholeText(): string {
    // TODO: Implement to concatenate adjacent text nodes
    return this.data;
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

  get data(): string {
    const content = super.data;
    const spaceIndex = content.indexOf(' ');
    return spaceIndex !== -1 ? content.slice(spaceIndex + 1) : '';
  }

  set data(value: string) {
    const target = this.target;
    super.data = value ? `${target} ${value}` : target;
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

// SAX Parser interface
export class SAXParser {
  public readonly ptr: Pointer;
  private callbacks: {
    onOpenTag?: (name: string, attributes: Record<string, string>) => void;
    onCloseTag?: (name: string) => void;
    onText?: (text: string) => void;
    onComment?: (comment: string) => void;
    onProcessingInstruction?: (target: string, data: string) => void;
    onCDATA?: (data: string) => void;
  } = {};

  constructor() {
    // TODO: Implement SAX parser creation with callbacks
    // This would require setting up callback functions that can be called from Zig
    throw new Error('SAX Parser not yet implemented');
  }

  setHandler(event: string, callback: Function): void {
    // TODO: Set event handlers
  }

  write(data: string): void {
    // TODO: Write data to SAX parser
  }

  free(): void {
    // TODO: Free SAX parser
  }
}

// Node creation factory
const nodeTypes: { [key: number]: new (ptr: Pointer) => Node } = {
  [NodeType.ELEMENT_NODE]: Element,
  [NodeType.ATTRIBUTE_NODE]: Attr,
  [NodeType.TEXT_NODE]: Text,
  [NodeType.CDATA_SECTION_NODE]: CDATASection,
  [NodeType.PROCESSING_INSTRUCTION_NODE]: ProcessingInstruction,
  [NodeType.COMMENT_NODE]: Comment,
  [NodeType.DOCUMENT_NODE]: Document,
} as const;

function createNode(ptr: Pointer): Node {
  const type = symbols.node_type(ptr);
  const Cls = nodeTypes[type];
  if (!Cls) {
    throw new Error(`Unknown node type: ${type}`);
  }
  return new Cls(ptr);
}

// Utility functions
export function parseXML(xmlString: string): Document | null {
  const docPtr = symbols.xml_parse(xmlString);
  if (!docPtr) return null;
  return createNode(docPtr) as Document;
}

// XPath evaluation at document level
export function evaluateXPath(xpath: string, contextNode: Node): XPathResult {
  return contextNode.selectNodes(xpath);
}

// Example usage:
function example() {
  // Create document structure
  const doc = new Document();
  const root = new Element('root');
  root.setAttribute('id', 'main');

  const child1 = new Element('child');
  child1.setAttribute('type', 'first');
  const text1 = new Text('Hello');
  child1.appendChild(text1);

  const child2 = new Element('child');
  child2.setAttribute('type', 'second');
  const text2 = new Text('World');
  child2.appendChild(text2);

  root.appendChild(child1);
  root.appendChild(child2);
  doc.appendChild(root);

  // XPath queries
  console.log('All children:', doc.selectNodes('//child').length);
  console.log('First type children:', doc.selectNodes('//child[@type="first"]').length);
  console.log('Text content of first child:', doc.selectSingleNode('//child[@type="first"]')?.textContent);

  // Alternative using convenience methods
  const firstChild = root.querySelector('.//child[@type="first"]');
  console.log('First child tag:', firstChild?.tagName);

  // Memory cleanup
  const result = doc.selectNodes('//child');
  result.forEach((node, index) => {
    console.log(`Child ${index}: ${(node as Element).getAttribute('type')}`);
  });
  result.free(); // Important: free XPath results

  // Free the document tree
  text1.free();
  text2.free();
  child1.free();
  child2.free();
  root.free();
  doc.free();
}

// Export the example for testing
export { example };
