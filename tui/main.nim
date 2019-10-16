import tui, termios

# Reset to cooked panel on exit
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
t.setFileFromProcArgs()
t.initialize()
while true:
  t.render()
  t.processKeypress(readKey())