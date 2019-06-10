type Attr* = enum
  resetAll
  bold
  dim
  italic
  underline
  blink
  reverse = 7
  hidden
  fgBlack = 30
  fgRed
  fgGreen
  fgYellow
  fgBlue
  fgMagenta
  fgCyan
  fgLightGray
  fgDefault = 39
  bgBlack
  bgRed
  bgGreen
  bgYellow
  bgBlue
  bgMagenta
  bgCyan
  bgLightGray
  bgDefault = 49
  fgDarkGray = 90
  fgLightRed
  fgLightGreen
  fgLightYellow
  fgLightBlue
  fgLightMagenta
  fgLightCyan
  fgWhite
  bgDarkGray = 100
  bgLightRed
  bgLightGreen
  bgLightYellow
  bgLightBlue
  bgLightMagenta
  bgLightCyan
  bgWhite

const
  eraseScreenCode* = "\e[2J"
  showCursorCode* = "\e[?25h"
  hideCursorCode* = "\e[?25l"

template cursorPosCode*(x, y): string =
  "\e[" & $(y + 1) & ";" & $(x + 1) & "H"

template cursorXPosCode*(x): string =
  "\e[" & $(x + 1) & "G"

template cursorForwardCode*(count): string =
  "\e[" & $count & "C"

template cursorBackwardCode*(count): string =
  "\e[" & $count & "D"

template toBg*(color): Attr = Attr(color.int + 10)

proc attrCode*(attrs: varargs[Attr]): string =
  result = "\e["
  for a in attrs:
    result &= $a.int & ";"
  result[^1] = 'm'
