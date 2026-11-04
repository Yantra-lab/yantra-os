## Navigation (Q5): a router with a back stack and paths ("/chat/42"), deep links
## ("yantra://app/chat/42?x=1"), and page transitions: a pushed page slides in from the
## right over the old one, a pop slides it back out. Nodes named alike on both pages
## (`text @avatar …` with a `transition`) fly between their places (the engine's heroes).
import std/[tables, strutils]
export tables
import ../core/[wire, runtime, signals]
import widgets, control, motion

type
  Params* = Table[string, string]      ## ":id" parts of the pattern, and ?query values
  Route* = object
    pattern*: string                   ## "/chat/:id"
    build*: proc (parent: Node; p: Params)
  Router* = ref object
    stack*: Signal[seq[string]]        ## the paths, the current one last
    forward: bool                      ## the last change was a push (for the transition)
    width*: float32                    ## how far pages slide (px)
    page: Node                         ## the page showing: its exit is set just before it goes

proc newRouter*(start = "/"): Router =
  Router(stack: newState(@[start]), forward: true, width: 420, page: Node(id: NodeId(-1)))

proc current*(r: Router): string = r.stack.get[^1]
proc canPop*(r: Router): bool = r.stack.get.len > 1

proc leaving(r: Router; pushed: bool) =
  if r.page.id.int32 < 0: return
  let w = r.width
  if pushed: r.page.setExit(fly(x = -w * 0.3, y = 0, opacity = 0.6, ms = 280))   # covered: drifts left
  else: r.page.setExit(fly(x = w, y = 0, opacity = 1.0, ms = 280))              # popped: slides out right

proc push*(r: Router; path: string) =
  r.leaving(true)
  r.forward = true
  r.stack.update(proc (s: var seq[string]) = s.add path)
proc pop*(r: Router) =
  if r.stack.peek.len <= 1: return
  r.leaving(false)
  r.forward = false
  r.stack.update(proc (s: var seq[string]) = s.setLen(s.len - 1))
proc replace*(r: Router; path: string) =
  r.leaving(true)
  r.forward = true
  r.stack.update(proc (s: var seq[string]) = s[^1] = path)
proc reset*(r: Router; path: string) =
  ## A new stack with only `path` (a tab switch, a deep link).
  r.leaving(true)
  r.forward = true
  r.stack.set(@[path])

proc deepLink*(url: string): string =
  ## "yantra://app/chat/42?x=1" (or just "/chat/42") -> "/chat/42?x=1".
  var u = url
  let scheme = u.find("://")
  if scheme >= 0:
    u = u[scheme + 3 .. ^1]
    let slash = u.find('/')
    u = if slash >= 0: u[slash .. ^1] else: "/"
  if not u.startsWith("/"): u = "/" & u
  u

proc openLink*(r: Router; url: string) = r.push(deepLink(url))

proc match*(pattern, path: string; params: var Params): bool =
  ## "/chat/:id" against "/chat/42?x=1" -> id = 42, x = 1. "*" matches the rest.
  params = initTable[string, string]()
  var p = path
  let q = p.find('?')
  if q >= 0:
    for kv in p[q + 1 .. ^1].split('&'):
      let eq = kv.find('=')
      if eq > 0: params[kv[0 ..< eq]] = kv[eq + 1 .. ^1] elif kv.len > 0: params[kv] = ""
    p = p[0 ..< q]
  let a = pattern.strip(chars = {'/'}).split('/')
  let b = p.strip(chars = {'/'}).split('/')
  for i, part in a:
    if part == "*": return true
    if i >= b.len: return part.len == 0
    if part.startsWith(":"): params[part[1 .. ^1]] = b[i]
    elif part != b[i]: return false
  a.len == b.len

proc routes*(parent: Node; r: Router; table: seq[Route]; notFound: proc (parent: Node) = nil) =
  ## The current page, in a stack that fills `parent`; pages come and go with a slide.
  let host = make(nkStack, parent)
  host.set(pFlexGrow, 1'f32)
  host.set(pClip, true)
  let top = proc (): seq[(int, string)] = @[(r.stack.get.len, r.stack.get[^1])]
  keyedList[(int, string)](host, top, proc (x: (int, string)): string = $x[0] & " " & x[1],
    proc (p: Node; x: (int, string)) =
      let page = make(nkColumn, p)
      page.set(pFlexGrow, 1'f32)
      page.set(pInsetTop, 0'f32); page.set(pInsetBottom, 0'f32)
      page.set(pInsetLeft, 0'f32); page.set(pInsetRight, 0'f32)
      let w = r.width
      page.setEnter(fly(x = (if r.forward: w else: -w * 0.3), y = 0, opacity = (if r.forward: 1.0 else: 0.6), ms = 280))
      page.setExit(fly(x = -w * 0.3, y = 0, opacity = 0.6, ms = 280))
      r.page = page                              # how it leaves is set when it does (`leaving`)
      var params: Params
      for rt in table:
        if match(rt.pattern, x[1], params):
          rt.build(page, params)
          return
      if notFound != nil: notFound(page))
