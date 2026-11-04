## chess/app.nim — Grandmaster's Study: a real chess game in Sutra. The position is a
## seq of 64 squares; the move generator is typed procs (blocking, pawn double-step,
## en passant, castling, checks, mate); tapping a square selects, tapping a second
## plays a legal move. One Canvas paints the lacquer frame, the brass fittings, the
## maple and walnut board, and the ivory and ebony set.

let
  room   = #0E120D        # the study at night
  desk   = #131A13        # the blotter the panel sits on
  felt   = #163023        # the baize of the captured tray
  plate  = #0A1410        # the status plate
  sheet  = #191308        # the score sheet
  ink    = #F6ECD6
  muted  = #9A927F
  brass  = #C9A45C
  brass2 = #F1D48F
  maple  = #D9BB91
  walnut = #7A4C30
  lac1   = #6B2E1B
  lac2   = #220A05
  bed    = #180A05
  ivory  = #F7F0E1
  ivoryL = #6B5638
  ebony  = #241C16
  ebonyL = #C9A45C
  files  = "abcdefgh"
  knDX   = [1, 2, 2, 1, -1, -2, -2, -1]
  knDY   = [2, 1, -1, -2, -2, -1, 1, 2]
  kgDX   = [1, 1, 0, -1, -1, -1, 0, 1]
  kgDY   = [0, 1, 1, 1, 0, -1, -1, -1]
  rdDX   = [1, -1, 0, 0]
  rdDY   = [0, 0, 1, -1]
  bdDX   = [1, 1, -1, -1]
  bdDY   = [1, -1, 1, -1]

proc col(c: Color): uint32 = uint32(c)
proc col(c: Color; a: float): uint32 = uint32(c.withAlpha(a))

type Mv = object
  ## One move of the generator: `flag` says what makes it special.
  src, dst: int
  flag: char   # ' ' quiet, 'd' double step, 'e' en passant, 'k'/'q' castling, 'p' promotion
  prom: char   # ' ' or the piece a pawn becomes

# ── the board, as 64 squares: "" or a side and a kind, "wP", "bK" ──────────────

proc sqIndex(r, f: int): int = r * 8 + f

proc sqName(i: int): string = $files[i mod 8] & $(i div 8 + 1)

proc sqLabel(r, f: int): string = sqName(sqIndex(7 - r, f))

proc isLight(r, f: int): bool =
  ## Display row `r` (0 is rank 8) and file `f`: the square's colour of the board.
  (7 - r + f) mod 2 == 1

proc sqFromName(name: string): int =
  ## "e2" -> its square; -1 when the text names no square.
  result = -1
  if name.len == 2 and name[0] >= 'a' and name[0] <= 'h' and name[1] >= '1' and name[1] <= '8':
    result = (ord(name[0]) - ord('a')) + (ord(name[1]) - ord('1')) * 8

proc onBoard(r, f: int): bool = r >= 0 and r < 8 and f >= 0 and f < 8

proc flip(s: char): char = (if s == 'w': 'b' else: 'w')

proc startPos(): seq[string] =
  ## The true starting position. Index 0 is a1, index 63 is h8.
  const back = "RNBQKBNR"
  result = newSeq[string](64)
  for i in 0 .. 63: result[i] = ""
  for f in 0 .. 7:
    result[f] = "w" & $back[f]
    result[8 + f] = "wP"
    result[48 + f] = "bP"
    result[56 + f] = "b" & $back[f]

proc noPlies(): seq[string] = @[]

proc kingSq(pos: seq[string]; side: char): int =
  result = -1
  for i in 0 .. 63:
    if pos[i].len == 2 and pos[i][0] == side and pos[i][1] == 'K': return i

proc attacked(pos: seq[string]; sq: int; side: char): bool =
  ## Whether `side` attacks square `sq`: pawns, knights, the king, then sliders.
  if sq < 0 or sq > 63: return false
  let r = sq div 8
  let f = sq mod 8
  let pr = (if side == 'w': r - 1 else: r + 1)
  for df in [-1, 1]:
    if onBoard(pr, f + df):
      let p = pos[sqIndex(pr, f + df)]
      if p.len == 2 and p[0] == side and p[1] == 'P': return true
  for k in 0 .. 7:
    let rr = r + knDY[k]
    let ff = f + knDX[k]
    if onBoard(rr, ff):
      let p = pos[sqIndex(rr, ff)]
      if p.len == 2 and p[0] == side and p[1] == 'N': return true
  for k in 0 .. 7:
    let rr = r + kgDY[k]
    let ff = f + kgDX[k]
    if onBoard(rr, ff):
      let p = pos[sqIndex(rr, ff)]
      if p.len == 2 and p[0] == side and p[1] == 'K': return true
  for k in 0 .. 3:
    var rr = r + rdDY[k]
    var ff = f + rdDX[k]
    while onBoard(rr, ff):
      let p = pos[sqIndex(rr, ff)]
      if p.len == 2:
        if p[0] == side and (p[1] == 'R' or p[1] == 'Q'): return true
        break
      rr += rdDY[k]
      ff += rdDX[k]
  for k in 0 .. 3:
    var rr = r + bdDY[k]
    var ff = f + bdDX[k]
    while onBoard(rr, ff):
      let p = pos[sqIndex(rr, ff)]
      if p.len == 2:
        if p[0] == side and (p[1] == 'B' or p[1] == 'Q'): return true
        break
      rr += bdDY[k]
      ff += bdDX[k]

proc inCheck(pos: seq[string]; side: char): bool =
  attacked(pos, kingSq(pos, side), flip(side))

proc slide(pos: seq[string]; s, r, f, dr, df: int; side: char; ms: var seq[Mv]) =
  ## Rook and bishop rays: every empty square, then one capture, then blocked.
  var rr = r + dr
  var ff = f + df
  while onBoard(rr, ff):
    let t = sqIndex(rr, ff)
    if pos[t].len == 2:
      if pos[t][0] != side: ms.add Mv(src: s, dst: t)
      return
    ms.add Mv(src: s, dst: t)
    rr += dr
    ff += df

proc pseudoMoves(pos: seq[string]; side: char; rights: string; epsq: int): seq[Mv] =
  ## Every move the pieces allow, before the king is checked for safety.
  var ms: seq[Mv] = @[]
  let other = flip(side)
  for s in 0 .. 63:
    let p = pos[s]
    if p.len != 2 or p[0] != side: continue
    let r = s div 8
    let f = s mod 8
    case p[1]
    of 'P':
      let d = (if side == 'w': 1 else: -1)
      let home = (if side == 'w': 1 else: 6)
      let last = (if side == 'w': 7 else: 0)
      let r1 = r + d
      if onBoard(r1, f) and pos[sqIndex(r1, f)].len == 0:
        if r1 == last: ms.add Mv(src: s, dst: sqIndex(r1, f), flag: 'p', prom: 'Q')
        else: ms.add Mv(src: s, dst: sqIndex(r1, f))
        if r == home and pos[sqIndex(r + 2 * d, f)].len == 0:
          ms.add Mv(src: s, dst: sqIndex(r + 2 * d, f), flag: 'd')
      for df in [-1, 1]:
        if not onBoard(r1, f + df): continue
        let t = sqIndex(r1, f + df)
        if pos[t].len == 2 and pos[t][0] == other:
          if r1 == last: ms.add Mv(src: s, dst: t, flag: 'p', prom: 'Q')
          else: ms.add Mv(src: s, dst: t)
        elif t == epsq:
          ms.add Mv(src: s, dst: t, flag: 'e')
    of 'N':
      for k in 0 .. 7:
        let rr = r + knDY[k]
        let ff = f + knDX[k]
        if onBoard(rr, ff):
          let t = sqIndex(rr, ff)
          if pos[t].len == 0 or pos[t][0] == other: ms.add Mv(src: s, dst: t)
    of 'K':
      for k in 0 .. 7:
        let rr = r + kgDY[k]
        let ff = f + kgDX[k]
        if onBoard(rr, ff):
          let t = sqIndex(rr, ff)
          if pos[t].len == 0 or pos[t][0] == other: ms.add Mv(src: s, dst: t)
      let home = (if side == 'w': 4 else: 60)
      if s == home and not attacked(pos, home, other):
        if side == 'w':
          if 'K' in rights and pos[7] == "wR" and pos[5].len == 0 and pos[6].len == 0 and
             not attacked(pos, 5, other) and not attacked(pos, 6, other):
            ms.add Mv(src: s, dst: 6, flag: 'k')
          if 'Q' in rights and pos[0] == "wR" and pos[1].len == 0 and pos[2].len == 0 and
             pos[3].len == 0 and not attacked(pos, 3, other) and not attacked(pos, 2, other):
            ms.add Mv(src: s, dst: 2, flag: 'q')
        else:
          if 'k' in rights and pos[63] == "bR" and pos[61].len == 0 and pos[62].len == 0 and
             not attacked(pos, 61, other) and not attacked(pos, 62, other):
            ms.add Mv(src: s, dst: 62, flag: 'k')
          if 'q' in rights and pos[56] == "bR" and pos[57].len == 0 and pos[58].len == 0 and
             pos[59].len == 0 and not attacked(pos, 59, other) and not attacked(pos, 58, other):
            ms.add Mv(src: s, dst: 58, flag: 'q')
    of 'R':
      for k in 0 .. 3: slide(pos, s, r, f, rdDY[k], rdDX[k], side, ms)
    of 'B':
      for k in 0 .. 3: slide(pos, s, r, f, bdDY[k], bdDX[k], side, ms)
    of 'Q':
      for k in 0 .. 3:
        slide(pos, s, r, f, rdDY[k], rdDX[k], side, ms)
        slide(pos, s, r, f, bdDY[k], bdDX[k], side, ms)
    else: discard
  result = ms

proc played(pos: seq[string]; m: Mv): seq[string] =
  ## The position after `m`: castling moves its rook, en passant takes behind.
  result = newSeq[string](64)
  for i in 0 .. 63: result[i] = pos[i]
  let p = result[m.src]
  result[m.src] = ""
  if m.flag == 'p': result[m.dst] = $p[0] & $m.prom
  else: result[m.dst] = p
  if m.flag == 'e':
    result[m.dst + (if p[0] == 'w': -8 else: 8)] = ""
  elif m.flag == 'k':
    let rook = result[m.dst + 1]
    result[m.dst + 1] = ""
    result[m.dst - 1] = rook
  elif m.flag == 'q':
    let rook = result[m.dst - 2]
    result[m.dst - 2] = ""
    result[m.dst + 1] = rook

proc legalMoves(pos: seq[string]; side: char; rights: string; epsq: int): seq[Mv] =
  ## The moves that leave your own king safe: the whole rule of chess in one filter.
  result = @[]
  for m in pseudoMoves(pos, side, rights, epsq):
    let nx = played(pos, m)
    if not attacked(nx, kingSq(nx, side), flip(side)): result.add m

proc targets(pos: seq[string]; side: char; rights: string; epsq, src: int): seq[Mv] =
  result = @[]
  for m in legalMoves(pos, side, rights, epsq):
    if m.src == src: result.add m

proc pickTo(ms: seq[Mv]; dst: int): Mv =
  result = Mv(src: -1, dst: -1)
  for m in ms:
    if m.dst == dst: return m

proc captureOf(pos: seq[string]; m: Mv): string =
  if m.flag == 'e': pos[m.dst + (if pos[m.src][0] == 'w': -8 else: 8)]
  else: pos[m.dst]

proc rightsAfter(rights: string; src, dst: int): string =
  result = ""
  for c in rights:
    var keep = true
    if c == 'K' and (src == 7 or dst == 7 or src == 4): keep = false
    elif c == 'Q' and (src == 0 or dst == 0 or src == 4): keep = false
    elif c == 'k' and (src == 63 or dst == 63 or src == 60): keep = false
    elif c == 'q' and (src == 56 or dst == 56 or src == 60): keep = false
    if keep: result.add c

proc epAfter(m: Mv): int = (if m.flag == 'd': (m.src + m.dst) div 2 else: -1)

proc sanOf(pos: seq[string]; side: char; rights: string; epsq: int; m: Mv): string =
  ## Algebraic notation, with the disambiguation real scoresheets need.
  let p = pos[m.src]
  if m.flag == 'k': result = "O-O"
  elif m.flag == 'q': result = "O-O-O"
  else:
    let cap = pos[m.dst].len == 2 or m.flag == 'e'
    if p[1] == 'P':
      result = (if cap: $files[m.src mod 8] & "x" else: "") & sqName(m.dst)
      if m.flag == 'p': result.add "=Q"
    else:
      var rival = false
      var sameFile = false
      var sameRank = false
      for o in legalMoves(pos, side, rights, epsq):
        if o.dst == m.dst and o.src != m.src and pos[o.src].len == 2 and pos[o.src][1] == p[1]:
          rival = true
          if o.src mod 8 == m.src mod 8: sameFile = true
          if o.src div 8 == m.src div 8: sameRank = true
      var dis = ""
      if rival:
        if not sameFile: dis = $files[m.src mod 8]
        elif not sameRank: dis = $(m.src div 8 + 1)
        else: dis = sqName(m.src)
      result = $p[1] & dis & (if cap: "x" else: "") & sqName(m.dst)
  let nx = played(pos, m)
  if inCheck(nx, flip(side)):
    if legalMoves(nx, flip(side), rightsAfter(rights, m.src, m.dst), epAfter(m)).len == 0:
      result.add "#"
    else: result.add "+"

proc statusLine(pos: seq[string]; side: char; rights: string; epsq: int): string =
  let chk = inCheck(pos, side)
  if legalMoves(pos, side, rights, epsq).len == 0:
    if chk: (if side == 'w': "Checkmate — Black wins" else: "Checkmate — White wins")
    else: "Stalemate — the game is drawn"
  elif chk: (if side == 'w': "White is in check" else: "Black is in check")
  else: (if side == 'w': "White to move" else: "Black to move")

proc statusNote(pos: seq[string]; side: char; rights: string; epsq, sel: int): string =
  let ms = legalMoves(pos, side, rights, epsq)
  if ms.len == 0: return "No legal moves left in this position"
  if sel >= 0:
    var n = 0
    for m in ms:
      if m.src == sel: inc n
    if n > 0: return sqName(sel) & " has " & $n & (if n == 1: " legal move" else: " legal moves")
  if inCheck(pos, side): return "The king must be answered"
  "Tap a piece, then the square it moves to"

proc pieceWord(k: char): string =
  case k
  of 'P': "pawn"
  of 'N': "knight"
  of 'B': "bishop"
  of 'R': "rook"
  of 'Q': "queen"
  of 'K': "king"
  else: "piece"

proc pieceValue(k: char): int =
  case k
  of 'P': 1
  of 'N', 'B': 3
  of 'R': 5
  of 'Q': 9
  else: 0

proc takenWords(caps: seq[string]; side: char): string =
  ## What the pieces of colour `side` that have left the board were.
  result = ""
  for c in caps:
    if c.len == 2 and c[0] == side:
      if result.len > 0: result.add ", "
      result.add (if side == 'w': "white " else: "black ") & pieceWord(c[1])
  if result.len == 0: result = "nothing yet"

proc materialLine(caps: seq[string]): string =
  var gain = 0
  for c in caps:
    if c.len == 2:
      if c[0] == 'b': gain += pieceValue(c[1])
      else: gain -= pieceValue(c[1])
  if gain == 0: "material level"
  elif gain > 0: "White +" & $gain
  else: "Black +" & $(-gain)

proc packPos(pos: seq[string]): string =
  result = ""
  for i in 0 .. 63:
    if pos[i].len == 2: result.add pos[i] else: result.add "--"

proc unpackPos(s: string): seq[string] =
  result = newSeq[string](64)
  for i in 0 .. 63:
    let a = i * 2
    if a + 1 < s.len and s[a] != '-': result[i] = $s[a] & $s[a + 1]
    else: result[i] = ""

proc savePoint(pos: seq[string]; side: char; rights: string; epsq, nm, nc, lf, lt: int): string =
  ## One ply of history, so Undo is exact.
  packPos(pos) & "|" & $side & "|" & rights & "|" & $epsq & "|" & $nm & "|" & $nc & "|" &
    $lf & "|" & $lt

# ── the set: ivory and ebony pieces, drawn as shapes in a 76-unit box ─────────

proc plateRect(d: var Draw; x, y, w, h, r: float32; fill, line: uint32) =
  d = d.rect(x - 0.7, y - 0.7, w + 1.4, h + 1.4, line, r + 0.7)
  d = d.rect(x, y, w, h, fill, r)

proc plateDisc(d: var Draw; cx, cy, r: float32; fill, line: uint32) =
  d = d.circle(cx, cy, r + 0.7, line)
  d = d.circle(cx, cy, r, fill)

proc platePath(d: var Draw; path: string; fill, line: uint32) =
  d = d.svgPath(path, 0.0, 0.0, 1.0, fill)
  d = d.svgPath(path, 0.0, 0.0, 1.0, line, 1.3)

proc pieceShape(d: var Draw; k: char; fill, line: uint32) =
  case k
  of 'P':
    plateRect(d, 22, 62, 32, 8, 3, fill, line)
    plateRect(d, 27, 56, 22, 6, 2, fill, line)
    platePath(d, "M32 57 L44 57 L46 44 L30 44 Z", fill, line)
    plateRect(d, 29, 39, 18, 5, 2, fill, line)
    plateDisc(d, 38, 31, 9, fill, line)
  of 'R':
    plateRect(d, 20, 62, 36, 8, 3, fill, line)
    platePath(d, "M25 62 L51 62 L49 32 L27 32 Z", fill, line)
    plateRect(d, 24, 25, 28, 8, 2, fill, line)
    plateRect(d, 24, 19, 7, 7, 1.5, fill, line)
    plateRect(d, 34.5, 19, 7, 7, 1.5, fill, line)
    plateRect(d, 45, 19, 7, 7, 1.5, fill, line)
  of 'N':
    plateRect(d, 20, 62, 36, 8, 3, fill, line)
    plateRect(d, 26, 56, 24, 6, 2, fill, line)
    platePath(d, "M26 57 C26 46 29 38 34 32 L33 20 L39 27 L43 17 L47 28 C55 30 60 34 61 40 " &
                 "C62 44 58 46 54 44 L48 40 C50 46 51 51 51 57 Z", fill, line)
  of 'B':
    plateRect(d, 23, 62, 30, 8, 3, fill, line)
    platePath(d, "M31 62 L45 62 L43 44 L33 44 Z", fill, line)
    plateRect(d, 30, 39, 16, 5, 2, fill, line)
    platePath(d, "M38 14 C48 24 50 33 38 40 C26 33 28 24 38 14 Z", fill, line)
    plateDisc(d, 38, 11, 3, fill, line)
  of 'Q':
    plateRect(d, 19, 62, 38, 8, 3, fill, line)
    platePath(d, "M27 62 L49 62 L47 44 L29 44 Z", fill, line)
    plateRect(d, 28, 39, 20, 5, 2, fill, line)
    platePath(d, "M29 40 L23 21 L32 29 L38 15 L44 29 L53 21 L47 40 Z", fill, line)
    plateDisc(d, 23, 21, 3, fill, line)
    plateDisc(d, 38, 15, 3.2, fill, line)
    plateDisc(d, 53, 21, 3, fill, line)
  of 'K':
    plateRect(d, 19, 62, 38, 8, 3, fill, line)
    platePath(d, "M27 62 L49 62 L47 42 L29 42 Z", fill, line)
    plateRect(d, 28, 37, 20, 5, 2, fill, line)
    plateRect(d, 26, 31, 24, 6, 2, fill, line)
    platePath(d, "M29 31 C29 21 47 21 47 31 Z", fill, line)
    plateRect(d, 35.4, 8, 5.2, 15, 1.4, fill, line)
    plateRect(d, 30.6, 12.4, 14.8, 5.2, 1.4, fill, line)
  else: discard

proc pieceDraw(d: var Draw; k: char; white: bool; x, y, size: float32) =
  ## A piece drawn in its 76-unit box, placed at (x, y) and scaled to `size`.
  let s = size / 76.0
  d = d.save()
  d = d.translate(x, y)
  d = d.scale(s)
  pieceShape(d, k, (if white: col(ivory) else: col(ebony)),
             (if white: col(ivoryL) else: col(ebonyL)))
  d = d.restore()

# ── the painting: a lacquer frame under the squares, the pieces over them ─────

proc boardFrame(): string =
  ## The board's furniture, painted once: lacquer, brass, its bed.
  let W: float32 = 748.0
  let M: float32 = 46.0
  let N: float32 = 656.0
  var d = Draw()
  d = d.linearRect(0.0, 0.0, W, W, col(lac1), col(lac2), W * 0.5, 0.0, W * 0.5, W, 18.0)
  d = d.noiseRect(0.0, 0.0, W, W, col(#C97A50, 0.26), col(#120402, 0.26), 0.02, 0.004, 4, 3.0, 18.0)
  d = d.linearRect(0.0, 0.0, W, W * 0.45, col(#FFFFFF, 0.08), col(#FFFFFF, 0.0),
                   0.0, 0.0, 0.0, W * 0.45, 18.0)
  # brass corner brackets, each with its screw
  for c in 0 .. 3:
    let bx = (if c mod 2 == 0: 9.0 else: W - 45.0)
    let by = (if c div 2 == 0: 9.0 else: W - 45.0)
    d = d.linearRect(bx, by, 36.0, 36.0, col(brass2, 0.9), col(#8D6A2F, 0.9),
                     bx, by, bx + 36.0, by + 36.0, 6.0)
    d = d.rect(bx + 5.0, by + 5.0, 26.0, 26.0, col(lac2, 0.55), 4.0)
    d = d.circle(bx + 18.0, by + 18.0, 4.6, col(#6E5125))
    d = d.circle(bx + 18.0, by + 18.0, 3.4, col(brass2))
  # a brass inlay line, everywhere but the corners
  d = d.line(20.0, 20.0, W - 20.0, 20.0, col(brass, 0.4), 1.5)
  d = d.line(20.0, W - 20.0, W - 20.0, W - 20.0, col(brass, 0.4), 1.5)
  d = d.line(20.0, 20.0, 20.0, W - 20.0, col(brass, 0.4), 1.5)
  d = d.line(W - 20.0, 20.0, W - 20.0, W - 20.0, col(brass, 0.4), 1.5)
  # the bed the squares sit in, ringed with brass
  d = d.rect(M - 9.0, M - 9.0, N + 18.0, N + 18.0, col(brass, 0.9), 5.0)
  d = d.rect(M - 6.0, M - 6.0, N + 12.0, N + 12.0, col(bed), 4.0)
  result = d.cmds

proc pieceArt(pos: seq[string]; side: char; rights: string; epsq, sel, lastF, lastT: int): string =
  ## What changes with the game: the last move, the picked square, its legal
  ## targets, the pieces, the coordinates, and the glaze over them all.
  let W: float32 = 748.0
  let M: float32 = 46.0
  let S: float32 = 82.0
  let N: float32 = 656.0
  var d = Draw()
  for r in 0 .. 7:
    for f in 0 .. 7:
      d = d.rect(M + float32(f) * S, M + float32(7 - r) * S, S, 1.0,
                 col(#FFFFFF, if isLight(r, f): 0.10 else: 0.05))
  for sp in [lastF, lastT]:
    if sp >= 0:
      d = d.rect(M + float32(sp mod 8) * S, M + float32(7 - sp div 8) * S, S, S, col(brass2, 0.20))
  if sel >= 0:
    let x = M + float32(sel mod 8) * S
    let y = M + float32(7 - sel div 8) * S
    d = d.rect(x + 1.0, y + 1.0, S - 2.0, S - 2.0, col(brass, 0.14), 3.0)
    d = d.line(x + 2.0, y + 2.0, x + S - 2.0, y + 2.0, col(brass2, 0.95), 2.5)
    d = d.line(x + 2.0, y + 2.0, x + 2.0, y + S - 2.0, col(brass2, 0.95), 2.5)
    d = d.line(x + S - 2.0, y + 2.0, x + S - 2.0, y + S - 2.0, col(brass2, 0.95), 2.5)
    d = d.line(x + 2.0, y + S - 2.0, x + S - 2.0, y + S - 2.0, col(brass2, 0.95), 2.5)
    for m in targets(pos, side, rights, epsq, sel):
      let tx = M + float32(m.dst mod 8) * S
      let ty = M + float32(7 - m.dst div 8) * S
      if pos[m.dst].len == 2 or m.flag == 'e':
        d = d.line(tx + 7.0, ty + 7.0, tx + S - 7.0, ty + 7.0, col(#1B1208, 0.42), 4.0)
        d = d.line(tx + 7.0, ty + 7.0, tx + 7.0, ty + S - 7.0, col(#1B1208, 0.42), 4.0)
        d = d.line(tx + S - 7.0, ty + 7.0, tx + S - 7.0, ty + S - 7.0, col(#1B1208, 0.42), 4.0)
        d = d.line(tx + 7.0, ty + S - 7.0, tx + S - 7.0, ty + S - 7.0, col(#1B1208, 0.42), 4.0)
      else:
        d = d.circle(tx + S * 0.5, ty + S * 0.5, 8.0, col(#1B1208, 0.34))
  let ks = kingSq(pos, side)
  if ks >= 0 and inCheck(pos, side):
    d = d.rect(M + float32(ks mod 8) * S + 1.0, M + float32(7 - ks div 8) * S + 1.0,
               S - 2.0, S - 2.0, col(#C0392B, 0.30), 3.0)
  for r in 0 .. 7:
    for f in 0 .. 7:
      let i = sqIndex(r, f)
      if pos[i].len == 2:
        let psz = S * 1.06
        let off = (S - psz) * 0.5
        pieceDraw(d, pos[i][1], pos[i][0] == 'w', M + float32(f) * S + off,
                  M + float32(7 - r) * S + off, psz)
  d = d.radialRect(0.0, 0.0, W, W, col(#000000, 0.0), col(#000000, 0.11),
                   W * 0.5, W * 0.5, W * 0.82)
  for k in 0 .. 7:
    let cx = M + (float32(k) + 0.5) * S
    let cy = M + (float32(k) + 0.5) * S
    d = d.text(cx - 3.5, M - 30.0, 13.0, col(brass2, 0.85), $files[k])
    d = d.text(cx - 3.5, M + N + 9.0, 13.0, col(brass2, 0.55), $files[k])
    d = d.text(M - 30.0, cy - 8.0, 13.0, col(brass2, 0.55), $(8 - k))
    d = d.text(M + N + 12.0, cy - 8.0, 13.0, col(brass2, 0.85), $(8 - k))
  result = d.cmds

proc trayArt(caps: seq[string]; side: char): string =
  ## The pieces of colour `side` that have been taken, laid on the baize.
  var d = Draw()
  var n = 0
  for c in caps:
    if c.len == 2 and c[0] == side:
      pieceDraw(d, c[1], side == 'w', 2.0 + float32(n) * 30.0, 0.0, 34.0)
      inc n
  result = d.cmds

proc discArt(side: char): string =
  var d = Draw()
  d = d.circle(11.0, 11.0, 10.0, col(brass, 0.9))
  d = d.circle(11.0, 11.0, 8.4, col(if side == 'w': ivory else: ebony))
  result = d.cmds

# ── the study ────────────────────────────────────────────────────────────────

view Chess
  state pos = startPos()
  state sel = -1
  state side = 'w'
  state rights = "KQkq"
  state epsq = -1
  state lastFrom = -1
  state lastTo = -1
  state moves = noPlies()
  state caps = noPlies()
  state past = noPlies()
  state frameArt = boardFrame()
  Column(fill = room, pad = 34px):
    Row(gap = 26px):
      Stack(width = 748px, height = 748px):
        Canvas(draw = frameArt, width = 748px, height = 748px)
        Column(absolute = true, top = 46px, left = 46px, width = 656px, height = 656px):
          for r in 0 .. 7:
            Row(gap = 0px):
              for f in 0 .. 7:
                Button "{sqLabel(r, f)}", width = 82px, height = 82px, fill = (if isLight(r, f): maple else: walnut), color = (if isLight(r, f): maple else: walnut), radius = 0px:
                  on tap:
                    let i = sqFromName(vjGetStr(vjTarget, 0))
                    if i >= 0:
                      if sel >= 0:
                        let m = pickTo(targets(pos, side, rights, epsq, sel), i)
                        if m.src >= 0:
                          past.add savePoint(pos, side, rights, epsq, moves.len, caps.len, lastFrom, lastTo)
                          moves.add sanOf(pos, side, rights, epsq, m)
                          let gone = captureOf(pos, m)
                          if gone.len == 2: caps.add gone
                          pos = played(pos, m)
                          rights = rightsAfter(rights, m.src, m.dst)
                          epsq = epAfter(m)
                          side = flip(side)
                          lastFrom = m.src
                          lastTo = m.dst
                          sel = -1
                        elif pos[i].len == 2 and pos[i][0] == side:
                          sel = i
                        else:
                          sel = -1
                      elif pos[i].len == 2 and pos[i][0] == side:
                        sel = i
        Canvas(draw = pieceArt(pos, side, rights, epsq, sel, lastFrom, lastTo), width = 748px, height = 748px, absolute = true, top = 0px, left = 0px)
      Panel(fill = desk, radius = 16px, pad = 22px, width = 438px):
        Column(gap = 14px):
          Text "A HOT-SEAT GAME FOR TWO", size = 11px, weight = 600, color = brass
          Text "Grandmaster's Study", size = 32px, weight = 700, color = ink
          Text "Tap a piece, then the square it moves to.", size = 13px, color = muted
          Panel(fill = plate, radius = 12px, pad = 14px):
            Row(gap = 12px):
              Canvas(draw = discArt(side), width = 22px, height = 22px)
              Column(gap = 3px):
                Text "{statusLine(pos, side, rights, epsq)}", size = 19px, weight = 600, color = ink
                Text "{statusNote(pos, side, rights, epsq, sel)}", size = 12px, color = muted
          Panel(fill = felt, radius = 12px, pad = 12px):
            Column(gap = 6px):
              Row(gap = 10px):
                Column(gap = 2px):
                  Text "WHITE TOOK", size = 10px, weight = 600, color = brass2
                  Text "{takenWords(caps, 'b')}", size = 10px, color = muted
                Canvas(draw = trayArt(caps, 'b'), width = 262px, height = 36px)
              Row(gap = 10px):
                Column(gap = 2px):
                  Text "BLACK TOOK", size = 10px, weight = 600, color = brass2
                  Text "{takenWords(caps, 'w')}", size = 10px, color = muted
                Canvas(draw = trayArt(caps, 'w'), width = 262px, height = 36px)
              Text "{materialLine(caps)}", size = 12px, color = brass2
          Panel(fill = sheet, radius = 12px, pad = 14px, grow = 1):
            Column(gap = 5px, scroll = true):
              Row(gap = 8px):
                Text "SCORE SHEET", size = 10px, weight = 600, color = brass
                Text "{moves.len} plies", size = 10px, color = muted
              for i in 0 ..< (moves.len + 1) div 2:
                Row(gap = 8px):
                  Text "{i + 1}.", size = 13px, color = muted, width = 26px
                  Text moves[2 * i], size = 14px, color = (if 2 * i == moves.len - 1: brass2 else: ink), width = 64px
                  if 2 * i + 1 < moves.len:
                    Text moves[2 * i + 1], size = 14px, color = (if 2 * i + 1 == moves.len - 1: brass2 else: ink), width = 64px
          Row(gap = 10px):
            Button "Undo", fill = #2A2118, color = brass2, radius = 10px, width = 186px, height = 42px:
              on tap:
                if past.len > 0:
                  let f = past[past.len - 1].split('|')
                  if f.len == 8:
                    pos = unpackPos(f[0])
                    side = f[1][0]
                    rights = f[2]
                    epsq = parseInt(f[3])
                    moves.setLen(parseInt(f[4]))
                    caps.setLen(parseInt(f[5]))
                    lastFrom = parseInt(f[6])
                    lastTo = parseInt(f[7])
                  past.setLen(past.len - 1)
                  sel = -1
            Button "New game", fill = brass, color = #2C1C0B, radius = 10px, width = 186px, height = 42px:
              on tap:
                pos = startPos()
                sel = -1
                side = 'w'
                rights = "KQkq"
                epsq = -1
                lastFrom = -1
                lastTo = -1
                moves.setLen(0)
                caps.setLen(0)
                past.setLen(0)
