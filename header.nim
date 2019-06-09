import os, termios, strutils, deques
from terminal import terminalHeight
import termiosutils, vt100

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
    bytesPerRow: int
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

template resetAndQuit() =
  stdout.write(eraseScreenCode & cursorPosCode(0, 0) & showCursorCode)
  quit()

template disableTimeout(code) =
  E.termios.c_cc[VMIN] = 1.cuchar
  setAttr(addr E.termios)
  code
  E.termios.c_cc[VMIN] = 0.cuchar
  setAttr(addr E.termios)

template toAscii(b: byte): string =
  case b.toByteKind
  of bkNull: "0"
  of bkWhiteSpace: "_"
  of bkPrintable: $b.char
  else: "x"

converter toInt(c: char): int = int(c)

converter toByteKind(b: byte): ByteKind =
  case b
  of 0x00: bkNull
  of 0x09 .. 0x0d, 0x20: bkWhiteSpace
  of 0x21 .. 0x7e: bkPrintable
  else: bkRest

proc editorInitiate()
proc editorProcessKeypress()
proc editorDrawRows(s: var string, panel: Panel)
