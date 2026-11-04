## A Vajra app's `fetch`, done by the host: only to the hosts the app declares
## (`uses network "api.example.com"`), and with its secrets filled in by the host, never
## seen by the app. A secret travels only to the host it was declared for
## (`uses secret "weather" -> "api.openweathermap.org"`): the app writes
## `secret("weather")`, a placeholder (`{{secret:weather}}`), and the host replaces it in
## the request it sends to that host, and refuses to send it anywhere else.
##
## The request comes packed as `method, url, body, name, value, name, value...`, each
## ending with \x1f (as a query's arguments do); the answer is `status\x1fbody`, or
## `\x15why` when the request is refused or fails.

import std/[strutils, monotimes, times]
import netrules
import ../libs/nimcurl/src/nimcurl

type
  Uses* = object
    hosts*: seq[string]                      ## `uses network "..."`
    secrets*: seq[(string, string, string)]  ## (name, the one host, the value)

const placeholderStart = "{{secret:"

proc fill(text, host: string; u: Uses; why: var string): string =
  ## `text` with each `{{secret:name}}` replaced by its value, if that secret is
  ## declared for `host`; otherwise `why` says what is wrong.
  result = text
  var at = result.find(placeholderStart)
  while at >= 0:
    let stop = result.find("}}", at)
    if stop < 0: break
    let name = result[at + placeholderStart.len ..< stop]
    var value = ""
    var found = false
    for (n, h, v) in u.secrets:
      if n == name:
        found = true
        if h != host:
          why = "secret " & name & " may only go to " & h
          return
        value = v
    if not found:
      why = "secret " & name & " is not declared: write `uses secret \"" & name & "\" -> \"" &
            host & "\"`"
      return
    result = result[0 ..< at] & value & result[stop + 2 .. ^1]
    at = result.find(placeholderStart, at + value.len)

proc vajraFetch*(u: Uses; packed: string; timeoutMs = 30_000): string =
  var parts = packed.split('\x1f')
  if parts.len < 4: return "\x15a malformed request"
  parts.setLen(parts.len - 1)
  let meth = parts[0]
  let url = parts[1]
  let (scheme, host) = urlHost(url)
  if host.len == 0: return "\x15not a web address: " & url
  if placeholderStart in url[0 ..< min(url.len, url.find(host) + host.len)]:
    return "\x15a secret cannot be part of a host's name"
  if not netAllowed(u.hosts.join(","), url):
    if scheme notin ["https", "http"] or (scheme == "http" and not isLocalHost(host)):
      return "\x15only https may leave this machine: " & url
    return "\x15" & host & " is not allowed: declare `uses network \"" & host & "\"`"
  var why = ""
  let fullUrl = fill(url, host, u, why)
  let body = fill(parts[2], host, u, why)
  var headers: seq[string] = @[]
  var i = 3
  while i + 1 < parts.len:
    headers.add parts[i] & ": " & fill(parts[i + 1], host, u, why)
    i += 2
  if why.len > 0: return "\x15" & why
  let f = newFetcher()
  defer: f.close()
  discard f.request(meth, fullUrl, headers, body, allowHttp = isLocalHost(host), timeoutMs = timeoutMs)
  let started = getMonoTime()
  while true:
    for r in f.poll():
      if r.status == 0: return "\x15the request failed: " & r.error
      return $r.status & "\x1f" & r.body
    if (getMonoTime() - started).inMilliseconds > timeoutMs + 1000:
      return "\x15no answer from " & host
    f.wait(50)
