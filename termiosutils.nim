import os, termios, terminal

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

proc die*(s: string) =
  eraseScreen()
  setCursorPos(0,0)
  showCursor()
  stderr.setForegroundColor(fgRed)
  stderr.write("Error: ")
  stderr.setForegroundColor(fgDefault)
  stderr.write(osLastError().osErrorMsg())
  if s != "":
    stderr.write(s)
  stderr.write("\r\n")
  quit()

proc getAttr*(termios: ptr Termios) {.raises: [OSError, IOError, ValueError].} =
  if tcGetAttr(0, termios) == -1: die "tcgetattr"

proc setAttr*(termios: ptr Termios) {.raises: [OSError, IOError, ValueError].} =
  if tcSetAttr(0, TCSAFLUSH, termios) == -1: die "tcsetattr"
