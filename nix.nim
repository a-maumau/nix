import system
import os
import terminal
import strutils
import sequtils
import strformat

import docopt

import termimode
import nixui

const
  NIX_VERSION = "0.1.0"

let doc = """
  nix

  Usage:
    nix [<file>]
    nix (-h | --help)
    nix --version

  Options:
    -h --help     Show this screen.
    --version     Show version.
  """

let args = docopt(doc, version=NIX_VERSION)

var
  ch: int = 0
  ui: nixui.UIManager

if args["<file>"]:
  ui = nixui.UIManager(filePath: $args["<file>"], topDescription:fmt"nix version {NIX_VERSION}")
else:
  ui = nixui.UIManager(topDescription:fmt"nix version {NIX_VERSION}")

ui.initInterface()
termimode.setTerminalRawMode()
while ch != 17:
  ui.printScreen()
  ch = ui.read()

  # for debugging
  #setCursorPos(1, terminalHeight())
  #eraseLine()
  #stdout.write(ch)

restoreTerminalMode()
showCursor()