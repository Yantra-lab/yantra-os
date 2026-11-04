## Where an app may reach on the network: absolute URLs, the hosts it lists, https
## (plain http only to this machine). Shared by the engine (host.nim) and the Vajra
## runtime (vajranet.nim).

import std/[os, strutils]

proc urlHost*(url: string): (string, string) =
  ## (scheme, host) of an absolute URL, lower case; ("", "") if it is not one we accept
  ## (no user@ part, no odd characters).
  let sep = url.find("://")
  if sep <= 0: return
  let scheme = url[0 ..< sep].toLowerAscii
  var rest = url[sep + 3 .. ^1]
  for stop in ['/', '?', '#']:
    let k = rest.find(stop)
    if k >= 0: rest = rest[0 ..< k]
  if '@' in rest or rest.len == 0: return
  var hostPart = rest
  if hostPart.startsWith("["): return                       # IPv6 literals: not yet
  let colon = hostPart.find(':')
  if colon >= 0:
    let port = hostPart[colon + 1 .. ^1]
    if port.len == 0 or not port.allCharsInSet({'0'..'9'}): return
    hostPart = hostPart[0 ..< colon]
  hostPart = hostPart.toLowerAscii
  if hostPart.len == 0 or not hostPart.allCharsInSet({'a'..'z', '0'..'9', '.', '-'}): return
  (scheme, hostPart)

proc isLocalHost*(h: string): bool = h in ["localhost", "127.0.0.1"]

proc netAllowed*(allow, url: string): bool =
  ## May an app whose window says `net = allow` fetch `url`? Its host must be listed
  ## ("api.example.com", or "*.example.com" for the subdomains), over https; plain http
  ## only to this machine. YANTRA_NET=off refuses everything.
  if getEnv("YANTRA_NET") == "off": return false
  let (scheme, h) = urlHost(url)
  if h.len == 0: return false
  if not (scheme in ["https", "wss"] or (scheme in ["http", "ws"] and isLocalHost(h))): return false
  for item in allow.split({',', ' '}):
    let a = item.strip.toLowerAscii
    if a.len == 0 or a == "*": continue
    if a == h: return true
    if a.startsWith("*.") and h.endsWith(a[1 .. ^1]) and h.len > a.len - 1: return true
  false

