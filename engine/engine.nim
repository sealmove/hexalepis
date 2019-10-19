const
  M = 512
  Mhalf = M div 2
  K = 2048
  Khalf = K div 2

type
  Node = ref object
    refCnt: int
    byteCnt: int64
    entries: int
    elements: array[M, Element]
    father: Node
    case isLeaf: bool
    of false: children: array[M, Node]
    of true: discard
  ElementKind = enum
    ekLiteral
    ekIoblock
  Element = ref object
    length: int64
    case kind: ElementKind
    of ekLiteral:
      bytes: array[K, byte]
    of ekIoblock:
      file: File
      offset: int64
  Tree* = object
    root: Node

proc find(n: Node, i: int64): tuple[p: ptr Element, offset: int64] =
  var
    i = i
    currElement = 0
  for c in 0 .. n.entries:
    case n.isLeaf
    of true:
      for e in 0 ..< n.entries:
        let
          element = unsafeAddr(n.elements[e])
          len = element.length.int64
        if i < len:
          return (element, i)
        else:
          i = i - len
    of false:
      let lcount = if n.children[c] == nil: 0'i64
                   else: n.children[c].byteCnt
      if i < lcount:
        return find(n.children[c], i)
      else:
        let
          e = unsafeAddr(n.elements[currElement])
          len = e.length.int64
        if i < lcount + len:
          return (e, i - lcount)
        else:
          i = i - lcount - len
          inc(currElement)

proc `[]`(n: Node, i: int64): byte =
  var (e, o) = find(n, i)
  case e.kind
  of ekLiteral:
    e.bytes[o]
  of ekIoblock:
    e.file.setFilePos(e.offset + o)
    readChar(e.file).byte

proc `[]=`(n: Node, i: int64, v: byte) =
  var (e, o) = find(n, i)
  case e.kind
  of ekLiteral:
    e.bytes[o] = v
  of ekIoblock:
    discard
    # Don't wanna touch the file here, should clone()

proc add(root: Node, where: int, what: Node) =
  if root.children[where] != nil:
    quit("Tried to add Node to non-nil link")
  what.father = root
  root.children[where] = what
  inc(root.entries)
  var curr = what
  while curr.father != nil:
    curr.father.byteCnt = curr.father.byteCnt + curr.byteCnt
    curr = curr.father

proc literal(b: array[K, byte], l: int): Element =
  Element(kind: ekLiteral, bytes: b, length: l)

proc ioblock(f: File, o: int64): Element =
  Element(length: f.getFileSize, kind: ekIoblock, file: f, offset: o)

proc `[]`*(t: Tree, i: int64): byte =
  t.root[i]

proc `[]=`*(t: Tree, i: int64, v: byte) =
  t.root[i] = v

proc len*(t: Tree): int64 =
  t.root.byteCnt

proc openFile*(f: File): owned Tree =
  var node = Node(byteCnt: f.getFileSize(), isLeaf: true, entries: 1)
  node.elements[0] = ioblock(f, 0)
  Tree(root: node)