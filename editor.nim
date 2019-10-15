{.experimental: "caseStmtMacros".}
import macros, strformat, imports/vt100

type byteState = enum
  bsHovering
  bsModified
  bsMarked

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

proc initiate() =
  # Enable raw mode
  setStdIoUnbuffered()
  E.termios = origTermios
  E.termios.c_iflag - {BRKINT, ICRNL, INPCK, ISTRIP, IXON}
  E.termios.c_oflag - {OPOST}
  E.termios.c_cflag + {CS8}
  E.termios.c_lflag - {ECHO, ICANON, IEXTEN, ISIG}
  E.termios.c_cc[VMIN] = 0.cuchar
  E.termios.c_cc[VTIME] = 1.cuchar
  setAttr(addr E.termios)

  # Initiate Editor
  E.scrnCols = 16
  E.scrnRowOff = 0
  E.scrnColOff = 0
  E.leftMargin = 11
  E.rightMargin = 2
  E.upperMargin = 1
  E.fileRowOff = 0
  E.fileColOff = 0
  E.userWidth = E.scrnCols
  E.panel = panelHex
  E.isPending = false
  E.undoStack = initDeque[tuple[index: int64, old, new: byte]]()
  E.redoStack = initDeque[tuple[index: int64, old, new: byte]]()
  stdout.write hideCursorCode

  # Read file if any
  if paramCount() >= 1:
    E.fileName = paramStr(1)
    var file: File
    try:
      file = open(paramStr(1))
      E.fileSize = getFileSize(file)
      E.fileData = newSeqOfCap[byte](E.fileSize)
      E.fileData.setLen(E.fileSize)
      let bytesRead = file.readBuffer(addr E.fileData[0], E.fileSize)
      if bytesRead != E.fileSize:
        die(&"Read {bytesRead} bytes instead of {E.fileSize}")
    except IOError:
      die("")
    finally:
      close(file)

  E.fileRows = E.fileData.len div E.scrnCols
  E.bytesInLastRow = E.fileData.len mod E.scrnCols
  if E.bytesInLastRow != 0:
    inc(E.fileRows)
  else:
    E.bytesInLastRow = E.scrnCols
  E.isModified = newSeq[bool](E.fileSize)
  E.isMarked = newSeq[bool](E.fileSize)

proc processKeypress() =
  let bytePos: int64 = E.scrnCols * (E.fileRowOff + E.scrnRowOff) +
                       E.fileColOff + E.scrnColOff

  include editor/processKeypress

  let c = readKey()
  case c
  of 0x0a .. 0x0d, 0x20 .. 0x7e:
    case E.panel
    of panelHex:
      if c in {'0'.int .. '9'.int, 'a'.int .. 'f'.int}:
        if E.isPending:
          E.isPending = false
          replace(fromHex[byte](E.pendingChar.char & c.char))
          clear(E.redoStack)
        else:
          E.isPending = true
          E.pendingChar = c
      elif c in {LEFT, DOWN, UP, RIGHT}:
        moveCursor(c)
      elif c == 'u'.int:
        undo()
      elif c == '-'.int or c == '='.int:
        adjustWidth(c)
      elif c == '['.int or c == ']'.int:
        horizontalScroll(c)
      elif c == 'm':
        mark()
    of panelAscii:
      E.isPending = false
      replace(c.byte)
      clear(E.redoStack)
      moveCursor(RIGHT)
  of CTRL('q'):
    resetAndQuit()
  of CTRL('s'):
    save()
  of CTRL('z'):
    undo()
  of CTRL('r'):
    redo()
  of LEFT_ARROW, DOWN_ARROW, UP_ARROW, RIGHT_ARROW:
    moveCursor(c)
  of PAGE_UP, PAGE_DOWN:
    verticalScroll(c)
  of HOME:
    E.scrnColOff = 0
  of END:
    E.scrnColOff = E.scrnCols - 1
  of TAB:
    case E.panel:
    of panelHex:
      E.panel = panelAscii
      E.isPending = false
    of panelAscii:
      E.panel = panelHex
  of ESC:
    E.isPending = false
  else: discard

# Buffered proc for drawing screen
proc drawRows(s: var string, panel: Panel) =
  s &= attrCode(fgYellow, bold, underline)
  let hoverOff = E.scrnCols * (E.fileRowOff + E.scrnRowOff) + E.fileColOff
  s &= toHex(hoverOff + E.scrnColOff, 8)
  s &= attrCode(resetAll)
  s &= "  "
  if panel == panelHex: s &= "|" else: s &= " "
  s &= attrCode(bold, fgYellow)
  for i in 0 ..< E.scrnCols:
    s &= i.toHex(2) & " "
  s &= "\b"
  s &= attrCode(resetAll)
  if panel == panelHex: s &= "|  "
  else: s &= "  |"
  s &= attrCode(bold, fgYellow)
  for i in 0 ..< E.scrnCols:
    s &= i.toHex(1)
  s &= eraseLineCode
  s &= attrCode(resetAll)
  if panel == panelAscii: s &= "|"
  s &= "\r\n"
  for row in 0 ..< E.scrnRows:
    s &= eraseLineCode
    let fileOff: int64 = E.scrnCols * (E.fileRowOff + row) + E.fileColOff
    if fileOff < E.fileSize:
      let upTo =
        if fileOff > E.fileSize - E.scrnCols:
          E.bytesInLastRow
        else:
          E.scrnCols
      s &= attrCode(bold)
      s &= fileOff.toHex(8).toLower & "  "
      s &= attrCode(resetAll)
      case panel
      of panelHex:
        s &= "|"
      of panelAscii:
        s &= " "
      for col in 0 ..< upTo:
        let
          scrnOff = fileOff + col
          isHovering = row == E.scrnRowOff and col == E.scrnColOff
        var
          kind: ByteKind
          color = E.fileData[scrnOff].getColor
          state: set[byteState]

        if E.isMarked[scrnOff]:   state.incl(bsMarked)
        if E.isModified[scrnOff]: state.incl(bsModified)
        if isHovering:            state.incl(bsHovering)

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

        if E.isPending and isHovering:
          s &= attrCode(bold, fgBlack, bgRed)
          s &= E.pendingChar.char
          s &= attrCode(resetAll)
          s &= attrCode(fgBlack, bgLightGray)
          s &= E.fileData[scrnOff].toHex.toLower[1]
          s &= attrCode(bold, fgBlack, bgRed)
        else:
          s &= E.fileData[scrnOff].toHex.toLower

        s &= cursorXPosCode(E.leftMargin + 3 * E.scrnCols + E.rightMargin +
                            col)
        s &= E.fileData[scrnOff].toAscii
        s &= attrCode(resetAll)
        s &= cursorXPosCode(E.leftMargin + 3 * (col + 1))
      if panel == panelHex:
        s &= cursorXPosCode(E.leftMargin + 3 * E.scrnCols - 1) & "|"
      else:
        s &= cursorXPosCode(E.leftMargin + 3 * E.scrnCols + 1) &
          "|" & cursorForwardCode(16) & "|"
    else:
      s &= "~"
    if row < E.scrnRows - 1:
      s &= "\r\n"
  s &= "\r\n"  #& attrCode(bgDarkGray)
  #for _ in 0 .. E.leftMargin + E.scrnCols + 17: s &= " "
  s &= attrCode(bgDefault)
