include header

var E: Editor
# Reset to cooked panel on exit
var origTermios: Termios
proc onQuit() {.noconv.} = setAttr(addr origTermios)
getAttr(addr origTermios)
addQuitProc(onQuit)

editorInitiate()

while true:
  E.scrnRows = terminalHeight() - 2
  # Render Screen
  var buf: string
  buf &= cursorPosCode(0, 0)
  editorDrawRows(buf, E.panel)
  buf &= cursorPosCode(E.leftMargin + E.scrnColOff,
                       E.upperMargin + E.scrnRowOff)
  stdout.write buf
  editorProcessKeypress()

proc editorInitiate() =
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
  E.scrnCols = 48
  E.scrnRowOff = 0
  E.scrnColOff = 0
  E.leftMargin = 11
  E.rightMargin = 2
  E.upperMargin = 1
  E.bytesPerRow = E.scrnCols div 3
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

  E.fileRows = E.fileData.len div E.bytesPerRow
  E.bytesInLastRow = E.fileData.len mod E.bytesPerRow
  if E.bytesInLastRow != 0:
    inc(E.fileRows)
  else:
    E.bytesInLastRow = E.bytesPerRow
  E.isModified = newSeq[bool](E.fileSize)

proc editorProcessKeypress() =
  proc readKey(): int =
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

  proc moveCursor(key: int) =
    case key
    of LEFT, LEFT_ARROW:
      if E.scrnColOff != 0:
        dec(E.scrnColOff, 3)
      elif E.scrnRowOff != 0:
        E.scrnColOff = E.scrnCols - 3
        dec E.scrnRowOff
      elif E.fileRowOff != 0:
        E.scrnColOff = E.scrnCols - 3
        dec E.fileRowOff
    of DOWN, DOWN_ARROW:
      # We are before pre-last row
      if E.fileRowOff + E.scrnRowOff < E.fileRows - 2:
        if E.scrnRowOff != E.scrnRows - 1:
          inc E.scrnRowOff
        else:
          inc E.fileRowOff
      # We are at pre-last row
      elif E.fileRowOff + E.scrnRowOff == E.fileRows - 2:
        if E.bytesInLastRow > E.scrnColOff div 3:
          if E.scrnRowOff == E.scrnRows - 1:
            inc E.fileRowOff
          else:
            inc E.scrnRowOff
    of UP, UP_ARROW:
      if E.scrnRowOff != 0:
        dec E.scrnRowOff
      elif E.fileRowOff != 0:
        dec E.fileRowOff
    of RIGHT, RIGHT_ARROW:
      # We are before last row
      if E.fileRowOff + E.scrnRowOff < E.fileRows - 1:
        if E.scrnColOff != E.scrnCols - 3:
          inc(E.scrnColOff, 3)
        else:
          if E.scrnRowOff == E.scrnRows - 1:
            inc E.fileRowOff
          else:
            inc E.scrnRowOff
          E.scrnColOff = 0
      # We are at last row
      else:
        if E.scrnColOff div 3 < E.bytesInLastRow - 1:
          inc(E.scrnColOff, 3)
    else: discard

  proc verticalScroll(key: int) =
    case key:
    of PAGE_UP:
      # We are first page
      if E.fileRowOff == 0:
        E.scrnRowOff = 0
      # Go to first page
      elif E.fileRowOff < E.scrnRows:
        if E.scrnRows - E.scrnRowOff < E.fileRowOff:
          E.scrnRowOff = E.scrnRows - 1
        else:
          inc(E.scrnRowOff, E.fileRowOff)
        E.fileRowOff = 0
      # Scroll full page
      else:
        dec(E.fileRowOff, E.scrnRows)
    of PAGE_DOWN:
      let remainingRows = E.fileRows - E.fileRowOff
      # We are at last page
      if remainingRows <= E.scrnRows:
        if E.bytesInLastRow > E.scrnColOff div 3:
          E.scrnRowOff = remainingRows - 1
        else:
          E.scrnRowOff = remainingRows - 2
      # Scroll full page
      elif remainingRows <= 2 * E.scrnRows:
        let rowsInLastPage = remainingRows - E.scrnRows
        if E.scrnRowOff > rowsInLastPage:
          dec(E.scrnRowOff, rowsInLastPage)
        else:
          E.scrnRowOff = 0
        inc(E.fileRowOff, rowsInLastPage)
      else:
        inc(E.fileRowOff, E.scrnRows)
    else: discard

  proc horizontalScroll(key: int) =
    template incBytesInLastRow() =
      if E.bytesInLastRow < 16:
        inc(E.bytesInLastRow)
      else:
        E.bytesInLastRow = 1

    template decBytesInLastRow() =
      if E.bytesInLastRow > 1:
        dec(E.bytesInLastRow)
      else:
        E.bytesInLastRow = 16

    case key
    of '['.int:
      if E.fileColOff != 0:
        dec(E.fileColOff)
        incBytesInLastRow()
      elif E.fileRowOff != 0:
        dec(E.fileRowOff)
        E.fileColOff = 15
        incBytesInLastRow()
    of ']'.int:
      if E.fileColOff != 15:
        inc(E.fileColOff)
        decBytesInLastRow()
      elif E.fileRowOff != E.fileRows:
        inc(E.fileRowOff)
        E.fileColOff = 0
        decBytesInLastRow()
    else: discard

  let c = readKey()
  case E.panel
  of panelHex:
    case c
    of '0'.int .. '9'.int, 'a'.int .. 'f'.int:
      if E.isPending:
        let
          newByte = fromHex[byte](E.pendingChar.char & c.char)
          bytePos: int64 = E.bytesPerRow * (E.fileRowOff + E.scrnRowOff) +
                           E.fileColOff + E.scrnColOff div 3
        E.undoStack.addLast((bytePos, E.fileData[bytePos]))
        E.fileData[bytePos] = newByte
        E.isModified[bytePos] = true
        moveCursor(RIGHT)
        E.isPending = false
      else:
        E.pendingChar = c
        E.isPending = true
        
    of CTRL('q'):
      resetAndQuit()
    of CTRL('s'):
      let
        file = open(E.fileName, fmWrite)
        bytesWrote = writeBytes(file, E.fileData, 0, E.fileData.len)
      close(file)
      if bytesWrote != E.fileData.len:
        die("Wrote " & $bytesWrote & "bytes instead of" & $E.fileData.len)
    of CTRL('u'), 'u'.int:
      if E.undoStack.len != 0:
        let oldByte = E.undoStack.popLast()
        E.fileData[oldByte.index] = oldByte.value
        E.isModified[oldByte.index] = false
    of LEFT, DOWN, UP, RIGHT, LEFT_ARROW, DOWN_ARROW, UP_ARROW, RIGHT_ARROW:
      moveCursor(c)
    of PAGE_UP, PAGE_DOWN:
      verticalScroll(c)
    of '['.int, ']'.int:
      horizontalScroll(c)
    of HOME:
      E.scrnColOff = 0
    of END:
      E.scrnColOff = E.scrnCols - 3
    of TAB:
      E.panel = panelAscii
      E.isPending = false
    of ESC:
      E.isPending = false
    else: discard
  of panelAscii:
    case c
    of 0x0a .. 0x0d, 0x20 .. 0x7e:
      E.isPending = false
      let bytePos: int64 = E.bytesPerRow * (E.fileRowOff + E.scrnRowOff) +
                           E.scrnColOff div 3
      E.undoStack.addLast((bytePos, E.fileData[bytePos]))
      E.fileData[bytePos] = c.byte
      E.isModified[bytePos] = true
      moveCursor(RIGHT)
    of CTRL('q'):
      resetAndQuit()
    of CTRL('s'):
      let
        file = open(E.fileName, fmWrite)
        bytesWrote = writeBytes(file, E.fileData, 0, E.fileData.len)
      close(file)
      if bytesWrote != E.fileData.len:
        die("Wrote " & $bytesWrote & "bytes instead of" & $E.fileData.len)
    of CTRL('u'):
      if E.undoStack.len != 0:
        let oldByte = E.undoStack.popLast()
        E.fileData[oldByte.index] = oldByte.value
        E.isModified[oldByte.index] = false
    of LEFT_ARROW, DOWN_ARROW, UP_ARROW, RIGHT_ARROW:
      moveCursor(c)
    of PAGE_UP, PAGE_DOWN:
      verticalScroll(c)
    of HOME:
      E.scrnColOff = 0
    of END:
      E.scrnColOff = E.scrnCols - 3
    of TAB:
      E.panel = panelHex
    else: discard

# Buffered proc for drawing screen
proc editorDrawRows(s: var string, panel: Panel) =
  template getBkAndColor(b: byte): tuple[bk: ByteKind, color: Attr] =
    case b
      of 0x00: (bkNull, fgDarkGray)
      of 0xff: (bkRest, fgDarkGray)
      of 0x09 .. 0x0d, 0x20: (bkWhiteSpace, fgBlue)
      of 0x21 .. 0x7e: (bkPrintable, fgCyan)
      else: (bkRest, fgWhite)

  s &= attrCode(fgYellow, bold, underline)
  let hoverOff = E.bytesPerRow * (E.fileRowOff + E.scrnRowOff) + E.fileColOff
  s &= toHex(hoverOff + E.scrnColOff div 3, 8)
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
    let fileOff: int64 = E.bytesPerRow * (E.fileRowOff + row) + E.fileColOff
    if fileOff < E.fileSize:
      let upTo =
        if fileOff > E.fileSize - E.bytesPerRow:
          E.bytesInLastRow
        else:
          E.bytesPerRow
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
          isHovering = row == E.scrnRowOff and col == E.scrnColOff div 3
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
        s &= cursorXPosCode(E.leftMargin + E.scrnCols + E.rightMargin + col)
        s &= E.fileData[scrnOff].toAscii
        s &= attrCode(resetAll)
        s &= cursorXPosCode(E.leftMargin + 3 * (col + 1))
      if panel == panelHex:
        s &= cursorXPosCode(E.leftMargin + E.scrnCols - 1) & "|"
      else:
        s &= cursorXPosCode(E.leftMargin + E.scrnCols + 1) &
          "|" & cursorForwardCode(16) & "|"
    else:
      s &= "~"
    if row < E.scrnRows - 1:
      s &= "\r\n"
  s &= "\r\n"  #& attrCode(bgDarkGray)
  #for _ in 0 .. E.leftMargin + E.scrnCols + 17: s &= " "
  s &= attrCode(bgDefault)
