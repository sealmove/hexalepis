import tui, termios, os

# Reset to cooked mode on exit
var origTerm: Termios
getAttr(addr origTerm)
proc onQuit() {.noconv.} = setAttr(addr origTerm)
addQuitProc(onQuit)

# Enable raw mode
var term = origTerm
setStdIoUnbuffered()
term.c_iflag - {BRKINT, ICRNL, INPCK, ISTRIP, IXON}
term.c_oflag - {OPOST}
term.c_cflag + {CS8}
term.c_lflag - {ECHO, ICANON, IEXTEN, ISIG}
term.c_cc[VMIN] = 0.cuchar
term.c_cc[VTIME] = 1.cuchar
setAttr(addr term)

# Run TUI
var t = new(Tui)
var file: File
if paramCount() >= 1:
  try:
    file = open(paramStr(1))
    t.setFileFromProcArgs(file)
  except IOError:
    die("")

t.initialize()
while true:
  t.render()
  t.processKeypress(readKey())

if file != nil:
  close(file)