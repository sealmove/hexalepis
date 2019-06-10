proc initiate() =
  # Enable raw panel
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
  E.panel = panelHex
  E.isPending = false
  E.undoStack = initDeque[tuple[index: int64, value: byte]]()
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
        die("Read " & $bytesRead & " bytes instead of " & $E.fileSize)
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
        else:
          E.isPending = true
          E.pendingChar = c
      elif c in {LEFT, DOWN, UP, RIGHT}:
        moveCursor(c)
      elif c == 'u'.int:
        undo()
      elif c == '['.int or c == ']'.int:
        horizontalScroll(c)
    of panelAscii:
      E.isPending = false
      replace(c.byte)
  of CTRL('q'):
    resetAndQuit()
  of CTRL('s'):
    save()
  of CTRL('z'):
    undo()
  of LEFT_ARROW, DOWN_ARROW, UP_ARROW, RIGHT_ARROW:
    moveCursor(c)
  of PAGE_UP, PAGE_DOWN:
    verticalScroll(c)
  of HOME:
    E.scrnColOff = 0
  of END:
    E.scrnColOff = E.scrnCols - 1
  of TAB:
    E.panel = panelAscii
    E.isPending = false
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
  s &= "0  1  2  3  4  5  6  7   8  9  A  B  C  D  E  F"
  s &= attrCode(resetAll)
  if panel == panelHex: s &= "|  "
  else: s &= "  |"
  s &= attrCode(bold, fgYellow)
  s &= "0123456789ABCDEF\e[K"
  s &= attrCode(resetAll)
  if panel == panelAscii: s &= "|"
  s &= "\r\n"
  for row in 0 ..< E.scrnRows:
    s &= "\e[K" # erase line 
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
        let scrnOff = fileOff + col
        var
          kind: ByteKind
          color: Attr
        (kind, color) = E.fileData[scrnOff].getBkAndColor
        var code: string
        let
          isHovering = row == E.scrnRowOff and col == E.scrnColOff
          hoverAttr = attrCode(fgBlack, color.toBg)
          overAttr = attrCode(bold, fgWhite, bgRed)
        if E.isPending and isHovering:
          s &= overAttr
          s &= E.pendingChar.char
          s &= attrCode(resetAll)
          s &= hoverAttr
          s &= E.fileData[scrnOff].toHex.toLower[1]
          s &= overAttr
        else:
          if isHovering:
            code = hoverAttr
          elif E.isModified[scrnOff]:
            code = overAttr
          else:
            code = attrCode(color)
          s &= code
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
