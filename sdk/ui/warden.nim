## Warden (C122 P4): the permissions shell, and the consent gate in front of it.
##
## Warden decides whether an action may run. A request that was never answered does not
## run. That is the whole point of this module and it is enforced in one place —
## `decide` — so no caller can skip it: there is no other function that returns "allowed".
##
## Two rules the drawer and the consent state exist to keep, both asserted in `t_warden`:
##
## 1. An OPEN DRAWER MUST BE ABLE TO CLOSE. `commitExpand` is only ever allowed to run
##    while the drawer is genuinely open, and after it commits the drawer is left closed
##    again. A drawer that can open but never close is the defect this guards against.
## 2. THE CONSENT FLAG MEANS CONSENT GIVEN. `granted` is true only once an answer has
##    actually arrived with `granted = true`. Asking is not consent: a pending request
##    resolves to denied, so a UI that shows a consent prompt and then proceeds anyway
##    cannot happen through this path.

type
  Capability* = enum
    capFiles, capTerminal, capNetwork, capBluetooth, capCamera, capMicrophone, capPayments

  Answer* = enum
    aPending,                    ## asked, not yet answered — OR never asked at all
    aGranted,                    ## the user said yes
    aDenied                      ## the user said no
  ##
  ## aPending is FIRST on purpose. A Drawer that has never been opened default-constructs
  ## to aPending, so "no answer yet" is the zero value and a default drawer can never look
  ## granted. Putting aGranted first would make every uninitialised drawer a consent slip.

  Scope* = enum
    scOnce,                      ## this one action
    scSession,                   ## until the shell closes
    scAlways                     ## every time, remembered

  Request* = object
    cap*: Capability
    subject*: string              ## what is being asked for: "Files in ~/Documents"
    scope*: Scope

  Decision* = enum
    dAsk,                        ## the user must answer first — the safe zero value
    dAllow,                      ## it may run
    dDeny                        ## it may not run
  ##
  ## dAsk is first for the same reason aPending is: a zero-initialised decision must never
  ## read as "allowed".

  Ledger* = object
    ## What the warden has been told to allow without asking. This is the remembered
    ## consent: a Grant for scAlways or scSession lands here.
    granted*: seq[Request]

proc scopeName*(s: Scope): string =
  case s
  of scOnce: "once"
  of scSession: "session"
  of scAlways: "always"

proc keyOf*(r: Request): string =
  ## The identity a remembered grant is filed under. Scope is part of the key, so a
  ## one-time "yes" can never be reused as a standing one.
  $r.cap & "|" & r.subject & "|" & r.scope.scopeName

proc grants*(ledger: Ledger; r: Request): bool =
  ## Whether a remembered grant covers this exact request (capability + subject + scope).
  let k = r.keyOf
  for g in ledger.granted:
    if g.keyOf == k: return true
  false

proc asks*(ledger: Ledger; r: Request): bool =
  ## Whether this request is not already covered by a remembered grant. A scOnce grant
  ## covers nothing later, so only a standing one counts.
  not ledger.grants(r)

proc decide*(ledger: Ledger; r: Request): Decision =
  ## The only path to "allowed". An unanswered request is dAsk, never dAllow: consent that
  ## has not been given cannot be read as consent by any caller.
  if ledger.asks(r): dAsk else: dAllow

proc consent*(ledger: var Ledger; r: Request; answer: Answer): bool =
  ## Record the user's answer to a consent prompt. Returns whether it now stands granted.
  case answer
  of aDenied: false
  of aPending:
    ## Nothing has been answered. Refusing to record anything here is what stops a UI
    ## that shows a prompt and then proceeds anyway: a pending prompt grants nothing.
    false
  of aGranted:
    if r.scope == scOnce:
      ## A one-time yes applies to this action only and is not remembered.
      true
    else:
      ledger.granted.add r
      true

proc allowed*(ledger: Ledger; r: Request; answer: Answer): bool =
  ## Whether THIS action may run, given the answer the user gave to this request.
  ##
  ## This is the function a caller uses, and it is what makes consent actually gate: only
  ## a real `aGranted` can produce true. `aPending` (the prompt is on screen, nobody has
  ## answered) and `aDenied` are both false, so a UI that shows consent and then proceeds
  ## anyway is not expressible through this path.
  ##
  ## Scope deliberately does NOT appear in the answer. The user's yes covers the action in
  ## hand whatever they chose; scope only decides whether `decide` has to ask again NEXT
  ## time. Mixing the two up is how "I said yes once" turns into a standing grant.
  case answer
  of aPending, aDenied: false
  of aGranted: true

# ---- the drawer ----------------------------------------------------------------------------------

type
  DrawerState* = enum
    drClosed,                    ## not showing
    drOpen                       ## showing

  Drawer* = object
    state*: DrawerState
    request*: Request
    answer*: Answer              ## the answer the user gave to `request`, aPending until one
    pending*: bool               ## true while a question is on screen and unanswered

proc openDrawer*(d: var Drawer; r: Request) =
  ## Opens the drawer on a fresh question. Opening again while already open is a no-op, so
  ## a double-open cannot strand it. It clears the previous answer, so a new question never
  ## inherits an old "yes".
  if d.state == drOpen: return
  d.state = drOpen
  d.request = r
  d.answer = aPending
  d.pending = true

proc closeDrawer*(d: var Drawer) =
  ## Closes the drawer, discarding the question on screen. This is the counterweight to
  ## openDrawer: an open drawer must always be closable.
  ##
  ## It deliberately leaves `answer` alone. Closing must not erase a verdict the user has
  ## already given — that verdict is what `runIfAllowed` reads — and it clears
  ## `pending` instead, so a later open cannot inherit a stale "yes" for a different ask.
  d.state = drClosed
  d.pending = false

proc isOpen*(d: Drawer): bool = d.state == drOpen

proc commitExpand*(d: var Drawer; answer: Answer; ledger: var Ledger): bool =
  ## Records the user's answer to the open drawer and closes it. Returns whether the
  ## action now stands granted.
  ##
  ## The rules, enforced here:
  ##   - a drawer that is not open commits nothing, so an expand cannot happen invisibly
  ##     behind a closed drawer;
  ##   - once it commits the drawer is CLOSED again, so an open drawer is never left
  ##     unable to close (this is the defect that made an open drawer un-closable);
  ##   - only aGranted grants. aPending and aDenied record nothing.
  if not d.isOpen: return false
  let granted = ledger.consent(d.request, answer)
  d.answer = answer
  d.closeDrawer()
  granted

proc runIfAllowed*(d: Drawer; ledger: Ledger): bool =
  ## What an app actually calls. The action runs only when there is no unanswered question
  ## on screen and the recorded answer is a real granted yes. A closed drawer that has
  ## never been answered is false, and so is one whose answer is pending or denied.
  not d.pending and ledger.allowed(d.request, d.answer)

# ---- what the page shows ---------------------------------------------------------------------------

proc requestLine*(r: Request): string =
  case r.cap
  of capFiles: "Read and write " & r.subject
  of capTerminal: "Run commands on this machine"
  of capNetwork: "Reach the network on your behalf"
  of capBluetooth: "Use nearby Bluetooth devices"
  of capCamera: "Use the camera"
  of capMicrophone: "Use the microphone"
  of capPayments: "Make payments for you"

proc explainScope*(s: Scope): string =
  case s
  of scOnce: "This time only"
  of scSession: "Until Yantra closes"
  of scAlways: "Every time, remembered"
