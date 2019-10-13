import os, termios, strutils, deques
from terminal import terminalHeight, terminalWidth
import imports/vt100
include header

# Reset to cooked panel on exit
proc onQuit() {.noconv.} = setAttr(addr origTermios)
getAttr(addr origTermios)
addQuitProc(onQuit)

include editor

initiate()

while true:
  E.scrnRows = terminalHeight() - 2
  E.widthMaxFit =
    (terminalWidth() - E.leftMargin - E.rightMargin - E.scrnCols) div 3
  if E.widthMaxFit < E.scrnCols:
    E.scrnCols = E.widthMaxFit
  elif E.widthMaxFit > E.userWidth:
    E.scrnCols = E.userWidth
  elif E.widthMaxFit > E.scrnCols + 1:
    E.scrnCols = E.widthMaxFit
  # Render Screen
  var buf: string
  buf &= cursorPosCode(0, 0)
  drawRows(buf, E.panel)
  buf &= cursorPosCode(E.leftMargin + 3 * E.scrnColOff,
                       E.upperMargin + E.scrnRowOff)
  stdout.write buf
  processKeypress()
