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
      dec(E.scrnColOff, 1)
    elif E.scrnRowOff != 0:
      E.scrnColOff = E.scrnCols - 1
      dec E.scrnRowOff
    elif E.fileRowOff != 0:
      E.scrnColOff = E.scrnCols - 1
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
      if E.bytesInLastRow > E.scrnColOff:
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
      if E.scrnColOff != E.scrnCols - 1:
        inc(E.scrnColOff, 1)
      else:
        if E.scrnRowOff == E.scrnRows - 1:
          inc E.fileRowOff
        else:
          inc E.scrnRowOff
        E.scrnColOff = 0
    # We are at last row
    else:
      if E.scrnColOff < E.bytesInLastRow - 1:
        inc(E.scrnColOff, 1)
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
      if E.bytesInLastRow > E.scrnColOff:
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
  proc incBytesInLastRow() =
    if E.bytesInLastRow < 16:
      inc(E.bytesInLastRow)
    else:
      E.bytesInLastRow = 1

  proc decBytesInLastRow() =
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

proc save() =
  let
    file = open(E.fileName, fmWrite)
    bytesWrote = writeBytes(file, E.fileData, 0, E.fileData.len)
  close(file)
  if bytesWrote != E.fileData.len:
    die("Wrote " & $bytesWrote & "bytes instead of" & $E.fileData.len)

proc replace(newByte: byte) =
  E.undoStack.addLast((bytePos, E.fileData[bytePos], newByte))
  E.fileData[bytePos] = newByte
  E.isModified[bytePos] = true
  moveCursor(RIGHT)

proc undo() =
  if E.undoStack.len != 0:
    let action = E.undoStack.popLast()
    E.redoStack.addLast(action)
    E.fileData[action.index] = action.old
    E.isModified[action.index] = false

proc redo() =
  if E.redoStack.len != 0:
    let action = E.redoStack.popLast()
    E.undoStack.addLast(action)
    E.fileData[action.index] = action.new
    E.isModified[action.index] = true
