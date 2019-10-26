import strformat

const
  M = 512
  Mhalf = M div 2
  K = 2048
  Khalf = K div 2

type
  Node = ref object
    refCnt: int
    byteCnt: int64
    depth: int
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

proc newRoot(): Node =
  Node(refCnt: 1, byteCnt: 0'i64, entries: 0)

proc add(n: Node, elements: varargs[Element]) =
  for i, e in elements:
    n.elements[n.entries + i] = e
    n.byteCnt = n.byteCnt + e.length
    var curr = n.father
    while curr != nil:
      curr.byteCnt = curr.byteCnt + e.length
      curr = curr.father
  inc(n.entries, elements.len)

proc add(n: Node, e: Element, where: int) =
  n.elements[where] = e
  n.byteCnt = n.byteCnt + e.length
  var curr = n.father
  while curr != nil:
    curr.byteCnt = curr.byteCnt + e.length
    curr = curr.father
  inc(n.entries)

proc add(root: Node, what: Node, where: int) =
  if root.children[where] != nil:
    quit("Tried to add Node to non-nil link")
  if what == nil:
    return
  what.father = root
  root.children[where] = what
  var curr = what
  while curr.father != nil:
    curr.father.byteCnt =  curr.father.byteCnt + curr.byteCnt
    if curr.father.depth <= curr.depth:
      curr.father.depth = curr.depth + 1
    curr = curr.father

proc get(n: Node, i: int64): tuple[p: Element, offset: int64] =
  var
    n = n
    i = i
  while true:
    var currElement = 0
    case n.isLeaf
    of true:
      for e in 0 ..< n.entries:
        if i < n.elements[e].length:
          return (n.elements[e], i)
        else:
          i = i - n.elements[e].length
    of false:
      for c in 0 .. n.entries:
        let lcount = if n.children[c] == nil: 0'i64
                     else: n.children[c].byteCnt
        # descent
        if i < lcount:
          n = n.children[c]
          break
        else:
          if n.elements[currElement] == nil:
            raise newException(IndexError, "index out of bounce")
          # found it
          elif i < lcount + n.elements[currElement].length:
            return (n.elements[currElement], i - lcount)
          # progress
          else:
            i = i - lcount - n.elements[currElement].length
            inc(currElement)

proc `[]`(n: Node, i: int64): byte =
  var (e, o) = get(n, i)
  case e.kind
  of ekLiteral:
    e.bytes[o]
  of ekIoblock:
    e.file.setFilePos(e.offset + o)
    readChar(e.file).byte

proc `[]=`(n: Node, i: int64, v: byte) =
  var (e, o) = get(n, i)
  case e.kind
  of ekLiteral:
    e.bytes[o] = v
  of ekIoblock:
    discard
    # Don't wanna touch the file here, should clone()

proc `[]`*(t: Tree, i: int64): byte =
  t.root[i]

proc `[]=`*(t: Tree, i: int64, v: byte) =
  t.root[i] = v

proc len*(t: Tree): int64 =
  t.root.byteCnt

proc height*(t: Tree): int =
  t.root.depth

proc ioblock(f: File, o: int64): Element =
  Element(length: f.getFileSize, kind: ekIoblock, file: f, offset: o)

proc openFile*(f: File): Tree =
  var node = Node(byteCnt: f.getFileSize(), isLeaf: true, entries: 1)
  node.elements[0] = ioblock(f, 0)
  Tree(root: node)

iterator path(t: Tree, i: int64): tuple[p: int, o: int64] =
  var
    n = t.root
    i = i
    isOver: bool
  while not isOver:
    var currElement = 0
    case n.isLeaf
    of true:
      for e in 0 ..< n.entries:
        if i < n.elements[e].length:
          isOver = true
          yield (e, i)
        else:
          i = i - n.elements[e].length
    of false:
      for c in 0 .. n.entries:
        let lcount = if n.children[c] == nil: 0'i64
                      else: n.children[c].byteCnt
        # descent
        if i < lcount:
          n = n.children[c]
          yield (c, i - lcount)
          break
        else:
          if n.elements[currElement] == nil:
            raise newException(IndexError, "index out of bounce")
          # found it
          elif i < lcount + n.elements[currElement].length:
            isOver = true
            yield (currElement, i - lcount)
            break
          # progress
          else:
            i = i - lcount - n.elements[currElement].length
            inc(currElement)

proc newLitElem(a: array[K, byte]; s, f: int64): Element =
  result = Element(kind: ekLiteral)
  for i in 0 .. f - s:
    result.bytes[i] = a[s + i]
  result.length = f - s + 1

proc split(t: Tree, at: int64): tuple[l, r: Tree] =
  var
    n = t.root
    levels: seq[tuple[l, r: Node, p: int]]

  for (p, o) in path(t, at):
    # Split point nodes
    let
      l = new(Node)
      r = new(Node)
    # Don't need to split any element in half
    if o < 0:
      for i in 0 ..< p:
        l.add(n.elements[i], i)
      for i in p ..< n.entries:
        r.add(n.elements[i], i - p)
      # Add all children except those at split point
      for i in 0 ..< p:
        l.add(n.children[i], i)
      for i in p + 1 .. n.entries:
        r.add(n.children[i], i - (p + 1) + 1)
    # Need to split an element in half
    else:
      for i in 0 ..< p:
        l.add(n.elements[i], i)
      l.add(newLitElem(n.elements[p].bytes, 0'i64, o), p)
      for i in p + 1 ..< n.entries:
        r.add(n.elements[i], i - p)
      r.add(newLitElem(n.elements[p].bytes, o + 1, n.elements[p].length-1), 0)
      # Add all children except those at split point
      for i in 0 .. p:
        l.add(n.children[i], i)
      for i in p + 1 .. n.entries:
        r.add(n.children[i], i - p + 1)
    # Save split point nodes
    levels.add((l, r, p))
    # Descent though split point
    n = n.children[p]

  # Add split point children
  for i in 0 ..< levels.len - 1:
    levels[i].l.add(levels[i+1].l, levels[i].l.entries)
    levels[i].r.add(levels[i+1].r, 0)

  return (Tree(root: levels[0].l), Tree(root: levels[0].r))

#proc join(l, r: Tree): Tree =


### TESTING AREA ###
proc newLitElem(s: varargs[int]): Element =
  result = Element(kind: ekLiteral)
  for i, b in s:
    result.bytes[i] = b.byte
  result.length = s.len

proc add(e: Element, what: seq[int], where: int) =
  for i, b in what:
    e.bytes[where + i] = b.byte
  e.length = e.length + what.len

when isMainModule:
  let
    n00 = new(Node)
    n01 = new(Node)
    n02 = new(Node)
    n03 = new(Node)
    n04 = new(Node)
    n05 = new(Node)
    n06 = new(Node)
    n07 = new(Node)
    n08 = new(Node)
    n09 = new(Node)
    n10 = new(Node)
    n11 = new(Node)
    e00 = newLitElem(0)
    e01 = newLitElem(1,2)
    e02 = newLitElem(3)
    e03 = newLitElem(4)
    e04 = newLitElem(5)
    e05 = newLitElem(6,7)
    e06 = newLitElem(8,9)
    e07 = newLitElem(10,11,12,13)
    e08 = newLitElem(14)
    e09 = newLitElem(15)
    e10 = newLitElem(16)
    e11 = newLitElem(17,18)
    e12 = newLitElem(19)
    e13 = newLitElem(20,21,22,23)
    e14 = newLitElem(24,25)
    e15 = newLitElem(26,27,28)
    e16 = newLitElem(29,30,31)

  n00.add(e00)
  n01.add(e01)
  n02.add(e02)
  n03.add(e03, e04)
  n04.add(e05, e07)
  n05.add(e06)
  n06.add(e08)
  n07.add(e09)
  n08.add(e10, e11, e16)
  n09.add(e12, e14)
  n10.add(e13)
  n11.add(e15)

  n02.add(n03, 1)
  n01.add(n00, 0)
  n01.add(n02, 1)
  n04.add(n01, 0)
  n04.add(n05, 1)
  n04.add(n08, 2)
  n06.add(n07, 1)
  n08.add(n06, 0)
  n09.add(n10, 1)
  n11.add(n09, 0)
  n08.add(n11, 2)

  let x = Tree(root: n04)

  echo "=== get() ==="
  block:
    var i: int
    while true:
      try:
        echo x[i]
      except IndexError:
        break
      inc(i)

  echo "\n"

  block:
    var j: int
    while true:
      echo &"=== split({j}) ==="
      try:
        echo "--- path() ---"
        for brk in path(x, j):
          echo brk
        let (l, r) = split(x, j)
        echo "--- left ---"
        block:
          var i: int
          while true:
            try:
              echo l[i]
            except IndexError:
              break
            inc(i)
        echo "--- right ---"
        block:
          var i: int
          while true:
            try:
              echo r[i]
            except IndexError:
              break
            inc(i)
        inc(j)
      except IndexError:
        break

  echo "=== height() ==="
  block:
    echo height(x)
