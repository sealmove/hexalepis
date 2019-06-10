type
  Editor = object
    termios: Termios
    scrnRows, scrnCols: int
    scrnRowOff, scrnColOff: int
    leftMargin, rightMargin, upperMargin: int
    fileName: string
    fileData: seq[byte]
    fileSize: int64
    fileRows: int
    fileRowOff: int
    fileColOff: int
    bytesInLastRow: int
    panel: Panel
    isPending: bool
    pendingChar: int
    undoStack: Deque[tuple[index: int64, value: byte]]
    isModified: seq[bool]
  ByteKind = enum
    bkPrintable
    bkWhitespace
    bkNull
    bkRest
  Panel = enum
    panelHex
    panelAscii

converter toInt(c: char): int = int(c)

converter toByteKind(b: byte): ByteKind =
  case b
  of 0x00: bkNull
  of 0x09 .. 0x0d, 0x20: bkWhiteSpace
  of 0x21 .. 0x7e: bkPrintable
  else: bkRest

# Keys
const
  ESC*        = '\e'
  TAB*        = '\t'
  LEFT*       = 'h'
  DOWN*       = 'j'
  UP*         = 'k'
  RIGHT*      = 'l'
  LEFT_ARROW  = 1000
  DOWN_ARROW  = 1001
  UP_ARROW    = 1002
  RIGHT_ARROW = 1003
  DEL*        = 1004
  HOME*       = 1005
  END*        = 1006
  PAGE_UP*    = 1007
  PAGE_DOWN*  = 1008
  NULL        = 9999

template CTRL*(k): int = k.int and 0b0001_1111

# Printing

#[template disableTimeout(code) =
  E.termios.c_cc[VMIN] = 1.cuchar
  setAttr(addr E.termios)
  code
  E.termios.c_cc[VMIN] = 0.cuchar
  setAttr(addr E.termios) ]#

template toAscii(b: byte): string =
  case b.toByteKind
  of bkNull: "0"
  of bkWhiteSpace: "_"
  of bkPrintable: $b.char
  else: "x"

template cursorHoverHexCode*(): string =
  cursorPosCode(E.leftMargin + E.scrnColOff, E.upperMargin + E.scrnRowOff)

template cursorHoverAsciiCode*(): string =
  let colOff = E.scrnColOff div 3
  cursorPosCode(E.leftMargin + E.scrnCols + E.rightMargin + colOff,
                E.upperMargin + E.scrnRowOff)

template getBkAndColor(b: byte): tuple[bk: ByteKind, color: Attr] =
  case b
    of 0x00: (bkNull, fgDarkGray)
    of 0xff: (bkRest, fgDarkGray)
    of 0x09 .. 0x0d, 0x20: (bkWhiteSpace, fgBlue)
    of 0x21 .. 0x7e: (bkPrintable, fgCyan)
    else: (bkRest, fgWhite)

# Termios utilities
const EAGAIN* = 11.OSErrorCode

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

template resetAndQuit() =
  stdout.write(eraseScreenCode & cursorPosCode(0, 0) & showCursorCode)
  quit()

template die*(errorMsg: string) =
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

proc getAttr*(termios: ptr Termios) {.raises: [IOError].} =
  if tcGetAttr(0, termios) == -1: die "tcgetattr"

proc setAttr*(termios: ptr Termios) {.raises: [IOError].} =
  if tcSetAttr(0, TCSAFLUSH, termios) == -1: die "tcsetattr"

# Main procedures
proc editorInitiate()
proc editorProcessKeypress()
proc editorDrawRows(s: var string, panel: Panel)