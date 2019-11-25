import
  vt100, macros, os, termios, deques, strutils, strformat, ../twkeng/twkeng
from terminal import terminalHeight, terminalWidth

type
  Tui* = ref object
    scrnRows, scrnCols: int
    scrnRowOff, scrnColOff: int
    leftMargin, rightMargin, upperMargin: int
    data: Tree
    size: int64
    rows: int
    rowOff: int
    colOff: int
    bytesInLastRow: int
    userWidth: int
    widthMaxFit: int
    panel: Panel
    isPending: bool
    pendingChar: int
  ByteKind = enum
    bkPrintable
    bkWhitespace
    bkNull
    bkRest
  Panel = enum
    panelHex
    panelAscii
  ByteState = enum
    bsHovering
    bsModified
    bsMarked

# Keys
const
  ESC         = '\e'.int
  TAB         = '\t'.int
  LEFT        = 'h'.int
  DOWN        = 'j'.int
  UP          = 'k'.int
  RIGHT       = 'l'.int
  LEFT_ARROW  = 1000
  DOWN_ARROW  = 1001
  UP_ARROW    = 1002
  RIGHT_ARROW = 1003
  DEL         = 1004
  HOME        = 1005
  END         = 1006
  PAGE_UP     = 1007
  PAGE_DOWN   = 1008
  NULL        = 9999

{.experimental: "caseStmtMacros".}
macro match(n: set): untyped =
  result = newTree(nnkIfStmt)
  let selector = n[0]
  for i in 1 ..< n.len:
    let it = n[i]
    case it.kind
    of nnkElse, nnkElifBranch, nnkElifExpr, nnkElseExpr:
      result.add it
    of nnkOfBranch:
      for j in 0..it.len-2:
        let cond = newCall("==", selector, it[j])
        result.add newTree(nnkElifBranch, cond, it[^1])
    else:
      error "'match' cannot handle this node", it

converter toInt(c: char): int = int(c)

converter toByteKind(b: byte): ByteKind =
  case b
  of 0x00: bkNull
  of 0x09 .. 0x0d, 0x20: bkWhiteSpace
  of 0x21 .. 0x7e: bkPrintable
  else: bkRest

template cursorHoverHexCode(t: Tui): string =
  cursorPosCode(t.leftMargin + t.scrnColOff, t.upperMargin + t.scrnRowOff)

template cursorHoverAsciiCode(t: Tui): string =
  let colOff = t.scrnColOff div 3
  cursorPosCode(t.leftMargin + t.scrnCols + t.rightMargin + colOff,
                t.upperMargin + t.scrnRowOff)

template bytePos(t): int64 = t.scrnCols * (t.rowOff + t.scrnRowOff) +
  t.colOff + t.scrnColOff

proc CTRL(k: char): int = k.int and 0b0001_1111

proc getColor(b: byte): Attr =
  case b
    of 0x00, 0xff: fgDarkGray
    of 0x09 .. 0x0d, 0x20: fgBlue
    of 0x21 .. 0x7e: fgCyan
    else: fgWhite

proc toAscii(b: byte): string =
  case b.toByteKind
  of bkNull: "0"
  of bkWhiteSpace: "_"
  of bkPrintable: $b.char
  else: "x"

  # Termios utilities
const EAGAIN = 11.OSErrorCode

template `-`*(flag: Cflag, exFlags: set[range[0..65535]]) =
  var x: Cflag
  for f in exFlags:
    x = x or f.Cflag
  flag = flag and not x

template `+`*(flag: Cflag, inFlags: set[range[0..65535]]) =
  var x: Cflag
  for f in inFlags:
    x = x or f.Cflag
  flag = flag or x

proc die*(errorMsg: string) =
  var sIn, sErr: string
  sIn &= eraseScreenCode
  sIn &= cursorPosCode(0,0)
  sIn &= showCursorCode
  stdout.write(sIn)
  sErr &= attrCode(fgRed)
  sErr &= "Error: "
  sErr &= attrCode(fgDefault)
  sErr &= osLastError().osErrorMsg()
  sErr &= "\r\n"
  if errorMsg != "":
    sErr &= errorMsg & "\r\n"
  stderr.write(sErr)
  quit()

proc resetAndQuit() =
  stdout.write(eraseScreenCode & cursorPosCode(0, 0) & showCursorCode)
  quit()

proc moveCursor(t: Tui, key: int) =
  case key
  of LEFT, LEFT_ARROW:
    if t.scrnColOff != 0:
      dec(t.scrnColOff, 1)
    elif t.scrnRowOff != 0:
      t.scrnColOff = t.scrnCols - 1
      dec t.scrnRowOff
    elif t.rowOff != 0:
      t.scrnColOff = t.scrnCols - 1
      dec t.rowOff
  of DOWN, DOWN_ARROW:
    # We are before pre-last row
    if t.rowOff + t.scrnRowOff < t.rows - 2:
      if t.scrnRowOff != t.scrnRows - 1:
        inc t.scrnRowOff
      else:
        inc t.rowOff
    # We are at pre-last row
    elif t.rowOff + t.scrnRowOff == t.rows - 2:
      if t.bytesInLastRow > t.scrnColOff:
        if t.scrnRowOff == t.scrnRows - 1:
          inc t.rowOff
        else:
          inc t.scrnRowOff
  of UP, UP_ARROW:
    if t.scrnRowOff != 0:
      dec t.scrnRowOff
    elif t.rowOff != 0:
      dec t.rowOff
  of RIGHT, RIGHT_ARROW:
    # We are before last row
    if t.rowOff + t.scrnRowOff < t.rows - 1:
      if t.scrnColOff != t.scrnCols - 1:
        inc(t.scrnColOff, 1)
      else:
        if t.scrnRowOff == t.scrnRows - 1:
          inc t.rowOff
        else:
          inc t.scrnRowOff
        t.scrnColOff = 0
    # We are at last row
    else:
      if t.scrnColOff < t.bytesInLastRow - 1:
        inc(t.scrnColOff, 1)
  else: discard

proc verticalScroll(t: Tui, key: int) =
  case key:
  of PAGE_UP:
    # We are first page
    if t.rowOff == 0:
      t.scrnRowOff = 0
    # Go to first page
    elif t.rowOff < t.scrnRows:
      if t.scrnRows - t.scrnRowOff < t.rowOff:
        t.scrnRowOff = t.scrnRows - 1
      else:
        inc(t.scrnRowOff, t.rowOff)
      t.rowOff = 0
    # Scroll full page
    else:
      dec(t.rowOff, t.scrnRows)
  of PAGE_DOWN:
    let remainingRows = t.rows - t.rowOff
    # We are at last page
    if remainingRows <= t.scrnRows:
      if t.bytesInLastRow > t.scrnColOff:
        t.scrnRowOff = remainingRows - 1
      else:
        t.scrnRowOff = remainingRows - 2
    # Scroll full page
    elif remainingRows <= 2 * t.scrnRows:
      let rowsInLastPage = remainingRows - t.scrnRows
      if t.scrnRowOff > rowsInLastPage:
        dec(t.scrnRowOff, rowsInLastPage)
      else:
        t.scrnRowOff = 0
      inc(t.rowOff, rowsInLastPage)
    else:
      inc(t.rowOff, t.scrnRows)
  else: discard

proc adjustWidth(t: Tui, key: int) =
  case key
  of '-'.int:
    if t.scrnCols > 1:
      dec(t.scrnCols)
      t.userWidth = t.scrnCols
  of '='.int:
    if t.scrnCols < t.widthMaxFit:
      inc(t.scrnCols)
      t.userWidth = t.scrnCols
  else: discard

proc horizontalScroll(t: Tui, key: int) =
  proc incBytesInLastRow() =
    if t.bytesInLastRow < 16: inc(t.bytesInLastRow) else: t.bytesInLastRow = 1

  proc decBytesInLastRow() =
    if t.bytesInLastRow > 1: dec(t.bytesInLastRow) else: t.bytesInLastRow = 16

  case key
  of '['.int:
    if t.colOff != 0:
      dec(t.colOff)
      incBytesInLastRow()
    elif t.rowOff != 0:
      dec(t.rowOff)
      t.colOff = 15
      incBytesInLastRow()
  of ']'.int:
    if t.colOff != 15:
      inc(t.colOff)
      decBytesInLastRow()
    elif t.rowOff != t.rows:
      inc(t.rowOff)
      t.colOff = 0
      decBytesInLastRow()
  else: discard

proc save(t: Tui) =
  discard

proc replace(t: Tui, newByte: byte) =
  t.data[t.bytePos] = newByte

proc undo(t: Tui) =
  discard

proc redo(t: Tui) =
  discard

proc mark(t: Tui) =
  discard

proc getAttr*(term: ptr Termios) {.raises: [IOError].} =
  if tcGetAttr(0, term) == -1: die "tcgetattr"

proc setAttr*(term: ptr Termios) {.raises: [IOError].} =
  if tcSetAttr(0, TCSAFLUSH, term) == -1: die "tcsetattr"

proc setFileFromProcArgs*(t: Tui, f: File) =
  t.data = openFile(f)
  t.size = getFileSize(f)

proc initialize*(t: Tui) =
  # Initialize Tui
  t.scrnCols = 16
  t.scrnRowOff = 0
  t.scrnColOff = 0
  t.leftMargin = 11
  t.rightMargin = 2
  t.upperMargin = 1
  t.rowOff = 0
  t.colOff = 0
  t.userWidth = t.scrnCols
  t.panel = panelHex
  t.isPending = false
  stdout.write hideCursorCode
  t.rows = t.data.len.int div t.scrnCols
  t.bytesInLastRow = t.data.len.int mod t.scrnCols
  if t.bytesInLastRow != 0:
    inc(t.rows)
  else:
    t.bytesInLastRow = t.scrnCols

# Buffered proc for drawing screen
proc render*(t: Tui) =
  t.scrnRows = terminalHeight() - 2
  t.widthMaxFit =
    (terminalWidth() - t.leftMargin - t.rightMargin - t.scrnCols) div 3
  if t.widthMaxFit < t.scrnCols:
    t.scrnCols = t.widthMaxFit
  elif t.widthMaxFit > t.userWidth:
    t.scrnCols = t.userWidth
  elif t.widthMaxFit > t.scrnCols + 1:
    t.scrnCols = t.widthMaxFit
  var s: string
  s &= cursorPosCode(0, 0)
  s &= attrCode(fgYellow, bold, underline)
  let hoverOff = t.scrnCols * (t.rowOff + t.scrnRowOff) + t.colOff
  s &= toHex(hoverOff + t.scrnColOff, 8)
  s &= attrCode(resetAll)
  s &= "  "
  if t.panel == panelHex: s &= "|" else: s &= " "
  s &= attrCode(bold, fgYellow)
  for i in 0 ..< t.scrnCols:
    s &= i.toHex(2) & " "
  s &= "\b"
  s &= attrCode(resetAll)
  if t.panel == panelHex: s &= "|  "
  else: s &= "  |"
  s &= attrCode(bold, fgYellow)
  for i in 0 ..< t.scrnCols:
    s &= i.toHex(1)
  s &= eraseLineCode
  s &= attrCode(resetAll)
  if t.panel == panelAscii: s &= "|"
  s &= "\r\n"
  for row in 0 ..< t.scrnRows:
    s &= eraseLineCode
    let off: int64 = t.scrnCols * (t.rowOff + row) + t.colOff
    if off < t.size:
      let upTo =
        if off > t.size - t.scrnCols:
          t.bytesInLastRow
        else:
          t.scrnCols
      s &= attrCode(bold)
      s &= off.toHex(8).toLower & "  "
      s &= attrCode(resetAll)
      case t.panel
      of panelHex:
        s &= "|"
      of panelAscii:
        s &= " "
      for col in 0 ..< upTo:
        let
          scrnOff = off + col
          isHovering = row == t.scrnRowOff and col == t.scrnColOff
        var
          kind: ByteKind
          color = t.data[scrnOff].getColor
          state: set[ByteState]

        if isHovering:
          state.incl(bsHovering)

        case state
        of {}:
          s &= attrCode(color)
        of {bsHovering}:
          s &= attrCode(fgBlack, color.toBg)
        of {bsModified}:
          s &= attrCode(fgBlack, bgRed)
        of {bsHovering, bsModified}:
          s &= attrCode(fgBlack, bgMagenta)
        of {bsMarked}:
          s &= attrCode(fgBlack, bgDarkGray)
        of {bsMarked, bsHovering}:
          s &= attrCode(fgBlack, bgLightGray)
        of {bsMarked, bsModified}:
          s &= attrCode(fgBlack, bgBlue)
        of {bsMarked, bsModified, bsHovering}:
          s &= attrCode(fgBlack, bgCyan)

        if t.isPending and isHovering:
          s &= attrCode(bold, fgBlack, bgRed)
          s &= t.pendingChar.char
          s &= attrCode(resetAll)
          s &= attrCode(fgBlack, bgLightGray)
          s &= t.data[scrnOff].toHex.toLower[1]
          s &= attrCode(bold, fgBlack, bgRed)
        else:
          s &= t.data[scrnOff].toHex.toLower

        s &= cursorXPosCode(t.leftMargin + 3 * t.scrnCols + t.rightMargin +
                            col)
        s &= t.data[scrnOff].toAscii
        s &= attrCode(resetAll)
        s &= cursorXPosCode(t.leftMargin + 3 * (col + 1))
      if t.panel == panelHex:
        s &= cursorXPosCode(t.leftMargin + 3 * t.scrnCols - 1) & "|"
      else:
        s &= cursorXPosCode(t.leftMargin + 3 * t.scrnCols + 1) &
          "|" & cursorForwardCode(16) & "|"
    else:
      s &= "~"
    if row < t.scrnRows - 1:
      s &= "\r\n"
  s &= "\r\n"  #& attrCode(bgDarkGray)
  #for _ in 0 .. t.leftMargin + t.scrnCols + 17: s &= " "
  s &= attrCode(bgDefault)
  s &= cursorPosCode(t.leftMargin + 3 * t.scrnColOff,
  t.upperMargin + t.scrnRowOff)
  stdout.write s

proc readKey*(): int =
  result = NULL
  var c: char
  let nread = readBuffer(stdin, addr c, 1)
  case nread
  of  1: result = c
  of -1: (if osLastError() != EAGAIN: die "read")
  else: return

  result = case result
  of ESC:
    var buf: array[3, char]
    if readBuffer(stdin, addr buf[0], 1) != 1: return
    if readBuffer(stdin, addr buf[1], 1) != 1: return
    if buf[0] == '[' and buf[1] in '0'..'9':
      if readBuffer(stdin, addr buf[2], 1) != 1: return

    case buf[0]
    of '[':
      case buf[1]
      of '0'..'9':
        case buf[2]
        of '~':
          case buf[1]:
          of '1': HOME
          of '3': DEL
          of '4': END
          of '5': PAGE_UP
          of '6': PAGE_DOWN
          of '7': HOME
          of '8': END
          else: ESC
        else: ESC
      of 'A': UP_ARROW
      of 'B': DOWN_ARROW
      of 'C': RIGHT_ARROW
      of 'D': LEFT_ARROW
      of 'F': END
      of 'H': HOME
      else: ESC
    of 'O':
      case buf[1]
      of 'F': END
      of 'H': HOME
      else: ESC
    else: ESC
  else: result  

proc processKeypress*(t: Tui, c: int) =
  case c
  of 0x0a .. 0x0d, 0x20 .. 0x7e:
    case t.panel
    of panelHex:
      if c in {'0'.int .. '9'.int, 'a'.int .. 'f'.int}:
        if t.isPending:
          t.isPending = false
          t.replace(fromHex[byte](t.pendingChar.char & c.char))
        else:
          t.isPending = true
          t.pendingChar = c
      elif c in {LEFT, DOWN, UP, RIGHT}:
        t.moveCursor(c)
      elif c == 'u'.int:
        t.undo()
      elif c == '-'.int or c == '='.int:
        t.adjustWidth(c)
      elif c == '['.int or c == ']'.int:
        t.horizontalScroll(c)
      elif c == 'm':
        t.mark()
    of panelAscii:
      t.isPending = false
      t.replace(c.byte)
      t.moveCursor(RIGHT)
  of CTRL('q'):
    resetAndQuit()
  of CTRL('s'):
    t.save()
  of CTRL('z'):
    t.undo()
  of CTRL('r'):
    t.redo()
  of LEFT_ARROW, DOWN_ARROW, UP_ARROW, RIGHT_ARROW:
    t.moveCursor(c)
  of PAGE_UP, PAGE_DOWN:
    t.verticalScroll(c)
  of HOME:
    t.scrnColOff = 0
  of END:
    t.scrnColOff = t.scrnCols - 1
  of TAB:
    case t.panel:
    of panelHex:
      t.panel = panelAscii
      t.isPending = false
    of panelAscii:
      t.panel = panelHex
  of ESC:
    t.isPending = false
  else: discard
