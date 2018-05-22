import system
import os
import terminal
import strutils

# this is for C lang, so writing in C style
const
  NCCS = 20
  TCSANOW = 0     # make change immediate
  TCSADRAIN = 1   # drain output, then change
  TCSAFLUSH = 2   # drain output, flush input

  ECHO: uint = 1 shl 3
  ICANON: uint = 1 shl 8

  STDIN_FILENO  = 0 # Standard input.
  STDOUT_FILENO = 1 # Standard output.
  STDERR_FILENO = 2 # Standard error output.

type termios = object
  c_iflag*: uint              # input mode flags
  c_oflag*: uint              # output mode flags
  c_cflag*: uint              # control mode flags
  c_lflag*: uint              # local mode flags
  c_line*: char               # line discipline
  c_cc*: array[NCCS, char]    # control characters
  c_ispeed*: int              # input speed 
  c_ospeed*: int              # output speed 

var
  oldt: termios
  newt: termios

  flagGetAttribute = false

# c functions
proc tcgetattr(f: int, t: ptr termios): void {. header: "<termios.h>", importc: "tcgetattr" .}
proc tcsetattr(f: int, s: int, t: ptr termios): void {. header: "<termios.h>", importc: "tcsetattr" .}

proc setTerminalRawMode*(): void =
  # Change terminal settings
  tcgetattr(0, oldt.addr)

  newt = oldt
  newt.c_lflag = newt.c_lflag and (not ICANON)
  newt.c_lflag = newt.c_lflag and (not ECHO)

  # Disable buffered IO
  tcsetattr(0, TCSANOW, newt.addr)
  flagGetAttribute = true

proc restoreTerminalMode*(): void =
  if flagGetAttribute == true:
    # Restore terminal settings
    tcsetattr(0, 1, oldt.addr)
