# nimcurl — interface

```nim
let f = newFetcher()
let id = f.start("https://api.example.com/x")          # > 0; https only unless allowHttp = true
let id2 = f.start(url, allowHttp = true, timeoutMs = 5000, maxBytes = 1 shl 20)
for r in f.poll():                                      # call often (each frame); never blocks
  echo r.id, r.status, r.body, r.error                  # status 0 = no answer; error says why
f.pending                                               # requests still on their way
f.wait(20)                                              # sleep until network activity or 20 ms
f.cancel(id)
f.close()
```

A 404 or 500 is an answer (its status), not an error. Redirects come back as their 3xx.
