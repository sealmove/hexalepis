const
  M = 4 # 512
  Mhalf = M div 2
  K = 4 # 2048
  Khalf = K div 2

type
  Node = ref object
    refCnt: int
    byteCnt: int
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
    of ekPlaceholder: file: tuple[offset, length: int]
  Tree* = object
    root: Node

proc `[]`(n: Node, i: int): byte =
  var
    i = i
    currElement = 0
  for c in 0 .. n.entries:
    case n.isLeaf
    of true:
      for e in 0 ..< n.entries:
        let
          element = n.elements[e]
          len = element.data.length
        if i < len:
          return element.data.bytes[i]
        else:
          dec(i, len)
    of false:
      let lcount = if n.children[c] == nil: 0
                   else: n.children[c].byteCnt
      if i < lcount:
        return n.children[c][i]
      else:
        let d = n.elements[currElement].data
        if i < lcount + d.length:
          return d.bytes[i - lcount]
        else:
          dec(i, lcount + d.length)
          inc(currElement)

#proc `[]`(t: Tree, i: int): byte =
#  t.root[i]

proc add(root: Node, where: int, what: Node) =
  if root.children[where] != nil:
    quit("Tried to add Node to non-nil link")
  what.father = root
  root.children[where] = what
  inc(root.entries)
  var curr = what
  while curr.father != nil:
    inc(curr.father.byteCnt, curr.byteCnt)
    curr = curr.father

proc elem(t: tuple[bytes: array[K, byte], length: int]): Element =
  Element(kind: ekLiteral, data: t)

let test = Node(
  isLeaf: false,
  entries: 2,
  elements: [elem(([12'u8,13,14,0], 3)),elem(([18'u8,19,0,0], 2)),nil,nil]
)

test.add(0, Node(
  byteCnt: 7,
  isLeaf: false,
  entries: 3,
  elements: [elem(([2'u8,3,4,5], 4)),
             elem(([7'u8,0,0,0], 1)),
             elem(([8'u8,9,0,0], 2)),
             nil]
))

test.children[0].add(0, Node(
  byteCnt: 2,
  isLeaf: true,
  entries: 1,
  elements: [elem(([0'u8,1,0,0], 2)),nil,nil,nil]
))

test.children[0].add(1, Node(
  byteCnt: 1,
  isLeaf: true,
  entries: 1,
  elements: [elem(([6'u8,0,0,0], 1)),nil,nil,nil]
))

test.children[0].add(3, Node(
  byteCnt: 2,
  isLeaf: true,
  entries: 2,
  elements: [elem(([10'u8,0,0,0], 1)), elem(([11'u8,0,0,0], 1)), nil, nil]
))

test.add(1, Node(
  byteCnt: 3,
  isLeaf: true,
  entries: 1,
  elements: [elem(([15'u8,16,17,0], 3)),nil,nil,nil]
))

test.add(2, Node(
  byteCnt: 8,
  isLeaf: false,
  entries: 2,
  elements: [elem(([20'u8,21,22,23], 4)),elem(([28'u8,29,30,31], 4)),nil,nil]
))

test.children[2].add(1, Node(
  byteCnt: 3,
  isLeaf: false,
  entries: 2,
  elements: [elem(([25'u8,26,0,0], 2)),elem(([27'u8,0,0,0], 1)),nil,nil]
))

test.children[2].children[1].add(0, Node(
  byteCnt: 1,
  isLeaf: true,
  entries: 1,
  elements: [elem(([24'u8,0,0,0], 1)),nil,nil,nil]
))

for i in 0 .. 31:
  echo test[i]