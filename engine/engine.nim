const
  M = 4 # 512
  Mhalf = M div 2
  K = 4 # 2048
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
    ekPlaceholder
  Element = ref object
    case kind: ElementKind
    of ekLiteral: data: tuple[bytes: array[K, byte], length: int]
    of ekPlaceholder: file: tuple[offset, length: int64]
  Tree* = object
    root: Node

var myFile = open("myfile", fmReadWriteExisting)

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
          len = case element.kind
                of ekLiteral:
                  element.data.length.int64
                of ekPlaceholder:
                  element.file.length
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
          len = case e.kind
                of ekLiteral:
                  e.data.length.int64
                of ekPlaceholder:
                  e.file.length
        if i < lcount + len:
          return (e, i - lcount)
        else:
          i = i - lcount - len
          inc(currElement)

proc `[]`(n: Node, i: int64): byte =
  var (e, o) = find(n, i)
  case e.kind
  of ekLiteral:
    e.data.bytes[o]
  of ekPlaceholder:
    myFile.setFilePos(e.file.offset + o)
    readChar(myFile).byte

proc `[]=`(n: Node, i: int64, v: byte) =
  var (e, o) = find(n, i)
  case e.kind
  of ekLiteral:
    e.data.bytes[o] = v
  of ekPlaceholder:
    discard
    # Don't wanna touch the file here, should clone()
    # myFile.setFilePos(e.file.offset + o)
    # myFile.write(v)

proc `[]`(t: Tree, i: int64): byte =
  t.root[i]

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

proc elemLiteral(t: tuple[bytes: array[K, byte], length: int]): Element =
  Element(kind: ekLiteral, data: t)

proc elemPlaceholder(offset, length: int64): Element =
  Element(kind: ekPlaceholder, file: (offset, length))

proc openFile(f: File): Tree =
  

let test = Node(
  isLeaf: false,
  entries: 2,
  elements: [elemLiteral(([12'u8,13,14,0], 3)),elemLiteral(([18'u8,19,0,0], 2)),nil,nil]
)

test.add(0, Node(
  byteCnt: 7,
  isLeaf: false,
  entries: 3,
  elements: [elemLiteral(([2'u8,3,4,5], 4)),
             elemLiteral(([7'u8,0,0,0], 1)),
             elemLiteral(([8'u8,9,0,0], 2)),
             nil]
))

test.children[0].add(0, Node(
  byteCnt: 2,
  isLeaf: true,
  entries: 1,
  elements: [elemLiteral(([0'u8,1,0,0], 2)),nil,nil,nil]
))

test.children[0].add(1, Node(
  byteCnt: 1,
  isLeaf: true,
  entries: 1,
  elements: [elemLiteral(([6'u8,0,0,0], 1)),nil,nil,nil]
))

test.children[0].add(3, Node(
  byteCnt: 2,
  isLeaf: true,
  entries: 2,
  elements: [elemLiteral(([10'u8,0,0,0], 1)), elemLiteral(([11'u8,0,0,0], 1)), nil, nil]
))

test.add(1, Node(
  byteCnt: 3,
  isLeaf: true,
  entries: 1,
  elements: [elemLiteral(([15'u8,16,17,0], 3)),nil,nil,nil]
))

test.add(2, Node(
  byteCnt: 8,
  isLeaf: false,
  entries: 2,
  elements: [elemPlaceholder(0, getFileSize(myFile)),elemLiteral(([28'u8,29,30,31], 4)),nil,nil]
))

test.children[2].add(1, Node(
  byteCnt: 3,
  isLeaf: false,
  entries: 2,
  elements: [elemLiteral(([25'u8,26,0,0], 2)),elemLiteral(([27'u8,0,0,0], 1)),nil,nil]
))

test.children[2].children[1].add(0, Node(
  byteCnt: 1,
  isLeaf: true,
  entries: 1,
  elements: [elemLiteral(([24'u8,0,0,0], 1)),nil,nil,nil]
))


test[5] = 55'u8
test[7] = 77'u8

for i in 0 .. 32:
  echo test[i]

close(myFile)