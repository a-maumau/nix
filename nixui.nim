import system
import os
import terminal
import strutils
import sequtils
import strformat

import termimode
import command

const
  ASCII_CODE_MARGIN = 224

  UnknownKey = -1
  WindowControlKey = -1
  UpArrowKey = 0+ASCII_CODE_MARGIN
  DownArrowKey = 1+ASCII_CODE_MARGIN
  RightArrowKey = 2+ASCII_CODE_MARGIN
  LeftArrowKey = 3+ASCII_CODE_MARGIN

  helpContent = "ctrl + o : open"

#proc getchar(): char {. importc: "getchar" .}

proc printableChar(ch: char): char =
  let ch_int = int(ch)
  if ch_int > 0x7E or ch_int < 0x20:
    return '.'
  return ch

proc isPrintable(ch: char): bool =
  let ch_int = int(ch)
  if ch_int > 0x7E or ch_int < 0x20:
    return false
  return true

proc eraseChar(): void =
  cursorBackward(stdout, 1)
  stdout.write(" ")
  cursorBackward(stdout, 1)

type UIManager* = ref object of RootObj
  # should be initialized
  filePath*: string
  topDescription*: string

  fileName: string
  data: string

  #[ terminal
    ______________________________
    |   A
    |   | <- hexWindowTopMargin
    |   V
    |<->  FF A0 BF ...
    | A
    | |--- hexWindowLeftMargin
    |
    |
    |     39 00 A5 ...
    |   A
    |   | <- hexWindowBottomMargin
    |   V
    |_____________________________

  ]#


  # for ui design
  hexAddrLen: int
  hexWindowTopMargin: int
  hexWindowBottomMargin: int
  hexWindowLeftMargin: int

  infobarMarginLeft: int

  # initial terminal size
  terminalW: int
  terminalH: int

  # for terminal position
  cursorTerminalPosX: int
  cursorTerminalPosY: int
  cursorTerminalLine: int

  # for hex editor position
  cursorHexWindowPosX: int
  cursorHexWindowPosY: int
  cursorHexWindowLine: int

  # for witch byte to highlight
  cursorBytesIndex: int

  lineIndex: int

  # tmp
  tmp_cursorTerminalPosX: int
  tmp_cursorTerminalPosY: int
  tmp_cursorTerminalLine: int
  tmp_cursorHexWindowPosX: int
  tmp_cursorHexWindowPosY: int
  tmp_cursorHexWindowLine: int
  tmp_cursorBytesIndex: int
  tmp_lineIndex: int

  # initial
  hexWindowCol: int
  hexWindowRow: int

  # state flag
  cmdCancel: bool
  infoAreaDirty: bool

# for good coding, I want arrange the procedures
# to more aligned order, but I don't know how to
# do forward declare for object type... :(

proc saveCursorPos(this: UIManager): void =
  this.tmp_cursorTerminalPosX = this.cursorTerminalPosX
  this.tmp_cursorTerminalPosY = this.cursorTerminalPosY
  this.tmp_cursorTerminalLine = this.cursorTerminalLine
  this.tmp_cursorHexWindowPosX = this.cursorHexWindowPosX
  this.tmp_cursorHexWindowPosY = this.cursorHexWindowPosY
  this.tmp_cursorHexWindowLine = this.cursorHexWindowLine
  this.tmp_cursorBytesIndex = this.cursorBytesIndex
  this.tmp_lineIndex = this.lineIndex

proc loadCursorPos(this: UIManager): void =
  this.cursorTerminalPosX = this.tmp_cursorTerminalPosX
  this.cursorTerminalPosY = this.tmp_cursorTerminalPosY
  this.cursorTerminalLine = this.tmp_cursorTerminalLine
  this.cursorHexWindowPosX = this.tmp_cursorHexWindowPosX
  this.cursorHexWindowPosY = this.tmp_cursorHexWindowPosY
  this.cursorHexWindowLine = this.tmp_cursorHexWindowLine
  this.cursorBytesIndex = this.tmp_cursorBytesIndex
  this.lineIndex = this.tmp_lineIndex

proc setCursor(this: UIManager, x, y: int): void = 
  setCursorPos(stdout, x, y)

proc setHexWindowCursor(this: UIManager, x, y: int): void = 
  # calc new highlight byte
  this.cursorBytesIndex = this.cursorBytesIndex + (x-this.cursorHexWindowPosX + this.hexWindowCol*(y-this.cursorHexWindowPosY))

  # for terminal position
  this.cursorTerminalPosX = this.hexWindowLeftMargin+1+(x-1)*3
  this.cursorTerminalPosY = this.hexWindowTopMargin+y # +1+(y-1)
  this.cursorTerminalLine = y+this.hexWindowTopMargin

  # for hex editor position
  this.cursorHexWindowPosX = x
  this.cursorHexWindowPosY = y
  this.cursorHexWindowLine = y

proc writeInfo(this: UIManager, msg: string=""): void =
  this.saveCursorPos()

  this.setCursor(1, this.terminalH-(this.hexWindowBottomMargin-2))
  stdout.write(msg)

  this.infoAreaDirty = true

  this.loadCursorPos()

proc moveCursor(this: UIManager, cmd: int): int =
  if cmd == UpArrowKey:
    if this.lineIndex == 0 and this.cursorHexWindowPosY == 1:
      this.setHexWindowCursor(1,1)
    elif this.cursorHexWindowPosY > 1:
      this.setHexWindowCursor(this.cursorHexWindowPosX, this.cursorHexWindowPosY-1)
    elif this.lineIndex > 0:
      this.lineIndex -= 1
      this.cursorBytesIndex -= this.hexWindowCol
  elif cmd == DownArrowKey:
    if this.data.len() == 0:
      discard
    # not at bottom row
    elif this.cursorHexWindowPosY < this.hexWindowRow and this.cursorBytesIndex+this.hexWindowCol < this.data.len():
      this.setHexWindowCursor(this.cursorHexWindowPosX, this.cursorHexWindowPosY+1)
    # at bottom row
    else:
      # if the next row is in the data length
      if this.hexWindowCol*(this.lineIndex+this.cursorHexWindowPosY)+this.cursorHexWindowPosX-1 < this.data.len():
        this.lineIndex += 1
        this.cursorBytesIndex += this.hexWindowCol
      # if the next row is out of data length
      else:
        var
          lastRow = int(this.data.len()/this.hexWindowCol)-(this.lineIndex-1)
          lastCol = ((this.data.len()-1) mod this.hexWindowCol)+1

        if this.cursorBytesIndex+(this.hexWindowRow-this.cursorHexWindowPosY) < this.data.len():
          if this.cursorBytesIndex <= (this.data.len()-1)-lastCol and this.cursorBytesIndex > (this.data.len()-1)-this.hexWindowCol and this.cursorHexWindowPosY == this.hexWindowRow:
            #if lastCol != this.hexWindowCol:
            this.lineIndex += 1
            this.cursorHexWindowPosY -= 1
            this.cursorTerminalPosY -= 1
            lastRow -= 1
        if lastCol == this.hexWindowCol:
          lastRow -= 1
        this.setHexWindowCursor(lastCol, lastRow)
  elif cmd == RightArrowKey:
    if this.cursorBytesIndex+1 >= this.data.len():
      discard
    elif this.cursorHexWindowPosX < this.hexWindowCol:
      this.setHexWindowCursor(this.cursorHexWindowPosX+1, this.cursorHexWindowPosY)
    elif this.cursorHexWindowPosX == this.hexWindowCol:
      if this.cursorHexWindowPosY == this.hexWindowRow:
        this.lineIndex += 1
        this.cursorHexWindowPosY -= 1
        this.cursorTerminalPosY -= 1
        this.setHexWindowCursor(1, this.hexWindowRow)
      else:
        this.setHexWindowCursor(1, this.cursorHexWindowPosY+1)
  elif cmd == LeftArrowKey:
    if this.cursorHexWindowPosX > 1:
      this.setHexWindowCursor(this.cursorHexWindowPosX-1 ,this.cursorHexWindowPosY)
    elif this.cursorHexWindowPosX == 1 and this.cursorBytesIndex > 0:
      if this.cursorHexWindowPosY == 1:
        this.lineIndex -= 1
        this.cursorHexWindowPosY += 1
        this.cursorTerminalPosY += 1
        this.setHexWindowCursor(this.hexWindowCol, this.cursorHexWindowPosY-1)
      else:
        this.setHexWindowCursor(this.hexWindowCol, this.cursorHexWindowPosY-1)

  return cmd

proc printTop(this: UIManager, text: string=""): void =
  this.saveCursorPos()

  this.setCursor(1, 1)

  # set the stdout style to reverse
  setStyle({styleReverse})
  
  stdout.write(fmt"{text}")
  for index in this.topDescription.len()..<this.terminalW:
    stdout.write(" ")

  # reset the style and color
  resetAttributes(stdout)

  this.loadCursorPos()

proc printHead(this: UIManager, highlight: bool=false): void = 
  this.saveCursorPos()

  this.setCursor(1, this.hexWindowTopMargin)

  stdout.write("addr")
  for index in 4..<this.hexAddrLen:
    stdout.write(" ")
  stdout.write(" | ")  

  for index in 0..<this.hexWindowCol:
    if highlight and index == this.cursorHexWindowPosX-1:
      setStyle({styleReverse})
      stdout.write(fmt"+{index:X}")
      resetAttributes(stdout)
      stdout.write(" ")
    else:
      stdout.write(fmt"+{index:X}")
      stdout.write(" ")

  stdout.write("| char")
  for index in 4..<this.hexWindowCol:
    stdout.write(" ")

  this.loadCursorPos()

proc printInfoBar(this: UIManager, desc: string=""): void =
  this.saveCursorPos() 
  
  this.setCursor(1, this.terminalH-(this.hexWindowBottomMargin-1))
  
  setStyle({styleReverse})
  stdout.write(" ".repeat(this.infobarMarginLeft))
  resetAttributes(stdout)
  
  stdout.write(fmt"{desc}")
  
  setStyle({styleReverse})
  for index in (fmt"{desc}".len()+this.infobarMarginLeft)..<this.terminalW:
    stdout.write(" ")
  
  resetAttributes(stdout)

  this.loadCursorPos()

proc printHelp(this: UIManager): void =
  this.writeInfo(helpContent)

proc initInterface*(this: UIManager): void = 
  this.fileName = ""
  this.data = ""
  this.cmdCancel = false

  this.hexAddrLen = 10
  this.hexWindowTopMargin = 2
  this.hexWindowBottomMargin = 2
  this.hexWindowLeftMargin = this.hexAddrLen+3

  # initial terminal size
  this.terminalW = terminalWidth()
  this.terminalH = terminalHeight()

  # for terminal position
  this.cursorTerminalPosX = this.hexWindowLeftMargin+1
  this.cursorTerminalPosY = this.hexWindowTopMargin+1
  this.cursorTerminalLine = 1+this.hexWindowTopMargin

  # for hex editor position
  this.cursorHexWindowPosX = 1
  this.cursorHexWindowPosY = 1
  this.cursorHexWindowLine = 1

  this.cursorBytesIndex = 0
  this.lineIndex = 0

  # initial
  if this.terminalW < 79:
    if this.terminalW < 48:
      this.hexWindowCol = 4
    else:
      this.hexWindowCol = 8
  else:
    this.hexWindowCol = 16
  this.hexWindowRow = this.terminalH-this.hexWindowTopMargin-this.hexWindowBottomMargin

  this.infobarMarginLeft = 3

  this.infoAreaDirty = false

  # init tmps
  this.saveCursorPos()

  eraseScreen()
  hideCursor()

  if not this.filePath.isNil():
    var f:File
    if open(f, this.filePath, FileMode.fmRead):
      defer:
        close(f)
        #echo("cannot open " & args["file"])
      this.data = f.readAll()
    if this.data == "":
      this.writeInfo("could not open \"" & this.filePath & "\"")
      this.fileName = ""
    else:
      var tmp = this.filePath.split('/')
      this.fileName = tmp[tmp.len()-1]
      discard

  this.printTop(this.topDescription)
  this.printHead(true)
  this.printInfoBar(this.fileName)

proc reloadInterface*(this: UIManager): void = 
  eraseScreen()

  this.cmdCancel = false

  # initial terminal size
  this.terminalW = terminalWidth()
  this.terminalH = terminalHeight()

  # for terminal position
  this.cursorTerminalPosX = this.hexWindowLeftMargin+1
  this.cursorTerminalPosY = this.hexWindowTopMargin+1
  this.cursorTerminalLine = 1+this.hexWindowTopMargin

  # for hex editor position
  this.cursorHexWindowPosX = 1
  this.cursorHexWindowPosY = 1
  this.cursorHexWindowLine = 1

  this.cursorBytesIndex = 0
  this.lineIndex = 0

  if this.terminalW < 79:
    if this.terminalW < 48:
      this.hexWindowCol = 4
    else:
      this.hexWindowCol = 8
  else:
    this.hexWindowCol = 16

  this.hexWindowRow = this.terminalH-this.hexWindowTopMargin-this.hexWindowBottomMargin

  this.infoAreaDirty = false

  this.saveCursorPos()
  
  this.printTop(this.topDescription)  
  this.printHead(true)
  this.printInfoBar(this.fileName)

  this.loadCursorPos()

proc scrollUp(this: UIManager): void =
  if this.cursorBytesIndex - this.hexWindowCol*this.hexWindowRow*2 < 0:
    this.setHexWindowCursor(1,1)
    this.cursorBytesIndex = 0
    this.lineIndex = 0
  else:
    this.cursorBytesIndex -= this.hexWindowCol*(this.hexWindowRow+1)
    this.lineIndex -= (this.hexWindowRow+1)

proc scrollDown(this: UIManager): void =
  if this.data.len() == 0:
    discard
  elif this.cursorBytesIndex + this.hexWindowCol*this.hexWindowRow*2 >= this.data.len():
    var
      allRow = int(this.data.len()/this.hexWindowCol)
      lastCol = ((this.data.len()-1) mod this.hexWindowCol)+1
    #this.setHexWindowCursor(lastCol, this.hexWindowRow-1)
    if lastCol == this.hexWindowCol:
      allRow -= 1
    this.setHexWindowCursor(lastCol, allRow-(this.lineIndex-1))
    this.cursorBytesIndex = this.data.len()-1
    if allRow-(this.hexWindowRow-2) > 0:
      this.lineIndex = allRow-(this.hexWindowRow-2)
    else:
      this.lineIndex = 0
  else:
    this.cursorBytesIndex += this.hexWindowCol*(this.hexWindowRow+1)
    this.lineIndex += (this.hexWindowRow+1)

proc eraseInfoArea(this: UIManager): void =
  let areaTop = this.terminalH-(this.hexWindowBottomMargin-2)
  for line in areaTop..this.terminalH:
    this.setCursor(1, line)
    eraseLine()

proc parseSpecialKey(this: UIManager): int =
  #[
    escaping? first 2 bytes
                  0x1B
                  0x5B

    up arrow    : 0x41
    down arrow  : 0x42
    right arrow : 0x43
    left arrow  : 0x44
  ]#

  var cmd = int(getch())
  if cmd == 0x5B:
    cmd = int(getch())
    case cmd:
      of 0x41:
        return UpArrowKey
      of 0x42:
        return DownArrowKey
      of 0x43:
        return RightArrowKey
      of 0x44:
        return LeftArrowKey
      else:
        return UnknownKey
  else:
    return int(cmd)

proc readString(this: UIManager, msg: string=""): string =
  var
    str:string = "" 
    input:char
    intInput:int = 0

  this.saveCursorPos()

  this.setCursor(1, this.terminalH)
  eraseLine()
  stdout.write(fmt"{msg}")

  while intInput != 13: # 13 is enter
    input = getch()
    intInput = int(input)
    case intInput:
      # ctrl+q
      of 17:
        this.cmdCancel = true
        intInput = 13
      of 127:
        if str.len() > 0:
          str.delete(str.len(), str.len())
          eraseChar()
      else:
        if isPrintable(input):
          str.add(input)
          stdout.write(input)

  eraseLine()
  this.loadCursorPos()
  return str

proc openFile(this: UIManager): void =
  var
    f:File
    tmpData:string = ""
    filePath = this.readString("Open:")

  if this.cmdCancel:
    this.cmdCancel = false
    return

  if open(f, filePath, FileMode.fmRead):
    defer:
      close(f)
      #echo("cannot open " & args["file"])
    tmpData = f.readAll()

  if tmpData == "":
    this.writeInfo("Could not open \"" & filePath & "\"")
  else:
    this.filePath = filePath
    var tmp = filePath.split('/')
    this.fileName = tmp[tmp.len()-1]
    this.data = tmpData
    this.reloadInterface()

proc read*(this: UIManager): int =
  var cmd = int(getch())

  if this.infoAreaDirty:
    this.eraseInfoArea()
    this.infoAreaDirty = false

  case cmd:
    of 0x1B:
      cmd = this.parseSpecialKey()
      return this.moveCursor(cmd)
    # ctrl+d
    of 4:
      this.scrollDown()
      return WindowControlKey
    # ctrl+f
    of 6:
      return WindowControlKey
    # ctrl+h
    of 8:
      this.printHelp()
      return WindowControlKey
    # ctrl+j
    of 10:
      return WindowControlKey
    # ctrl+o
    of 15:
      this.openFile()
      return WindowControlKey
    # ctrl+q
    of 17:
      return cmd
    # ctrl+u
    of 21:
      this.scrollUp()
      return WindowControlKey
    else:
      return cmd

proc printAddr(this: UIManager, headAddr: int, highlight: bool=false): void =
  if highlight:
    setStyle({styleReverse})
    stdout.write(fmt"{headAddr:#010X}")
    resetAttributes(stdout)
  else:
    stdout.write(fmt"{headAddr:#010X}")

proc printHex(this: UIManager, beginIndex: int, endIndex: int): void =
  # for optimization
  if endIndex > this.data.len():
    for index in beginIndex..<endIndex:
      if index < this.data.len():
        if this.cursorBytesIndex == index:
          setStyle({styleReverse})
          stdout.write(toHex(printableChar(this.data[index])))
          resetAttributes(stdout)
        else:
          stdout.write(toHex(printableChar(this.data[index])))

        stdout.write(" ")
      else:
        stdout.write("   ")
  else:
    for index in beginIndex..<endIndex:
      if this.cursorBytesIndex == index:
        setStyle({styleReverse})
        stdout.write(toHex(printableChar(this.data[index])))
        resetAttributes(stdout)
      else:
        stdout.write(toHex(printableChar(this.data[index])))

      stdout.write(" ")

proc printChars(this: UIManager, beginIndex: int, endIndex: int): void =
  if endIndex > this.data.len():
    for index in beginIndex..<endIndex:
      if index < this.data.len():
        if this.cursorBytesIndex == index:
          setStyle({styleReverse})
          stdout.write(printableChar(this.data[index]))
          resetAttributes(stdout)
        else:
          stdout.write(printableChar(this.data[index]))
      else:
        stdout.write(" ")
  else:
    for index in beginIndex..<endIndex:
      if this.cursorBytesIndex == index:
        setStyle({styleReverse})
        stdout.write(printableChar(this.data[index]))
        resetAttributes(stdout)
      else:
        stdout.write(printableChar(this.data[index]))

proc printLine(this: UIManager, beginIndex: int, endIndex: int, highlight: bool=false): void =
  this.printAddr(beginIndex, highlight)
  stdout.write(" | ")
  this.printHex(beginIndex, endIndex)
  stdout.write("| ")
  this.printChars(beginIndex, endIndex)

proc printLines(this: UIManager): void =
  for line in 0..<this.hexWindowRow-1:
    this.printLine(this.hexWindowCol*(line+this.lineIndex), this.hexWindowCol*(line+1+this.lineIndex), line+1==this.cursorHexWindowPosY)
    stdout.write("\n")

  this.printLine(this.hexWindowCol*(this.hexWindowRow-1+this.lineIndex), this.hexWindowCol*(this.hexWindowRow+this.lineIndex), this.hexWindowRow==this.cursorHexWindowPosY)

proc printScreen*(this: UIManager): void =
  # it looks like axis start from 1, so left top corner is (1,1)
  this.printHead(true)
  this.setCursor(1, this.hexWindowTopMargin+1)
  this.printLines()
  this.setCursor(this.cursorTerminalPosX, this.cursorTerminalPosY)


