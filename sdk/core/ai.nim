## AI: ask a language model. The app never holds a key: the host adds it (ANTHROPIC_API_KEY,
## read from its environment, never stored) or talks to a local model server (YANTRA_AI_URL,
## any OpenAI-compatible one: llama.cpp, Ollama). The app must declare `needs("ai")`.
##   aiAsk(@[AiTurn(role: "user", text: "Hi")], "You are…", proc (ok: bool; text: string) = …)

import std/json
import runtime

type AiTurn* = object
  role*: string               ## "user" or "assistant"
  text*: string

proc yAi(req, reqLen, handler: int32): int32 {.importc: "y_ai", cdecl.}
proc yAiReady(): int32 {.importc: "y_ai_ready", cdecl.}

proc aiReady*(): int =
  ## 0: no model is set up on this machine, 1: a hosted model (Claude), 2: a local model server.
  int(yAiReady())

proc answerText(body: string): (bool, string) =
  ## The text of a model's answer, from either API's shape; (false, why) if there is none.
  try:
    let j = parseJson(body)
    if j.hasKey("content"):                              # Anthropic Messages API
      var t = ""
      for part in j["content"]:
        if part{"type"}.getStr == "text": t.add part["text"].getStr
      return (true, t)
    if j.hasKey("choices") and j["choices"].len > 0:     # OpenAI-compatible (local servers)
      return (true, j["choices"][0]{"message"}{"content"}.getStr)
    if j.hasKey("error"):
      return (false, j["error"]{"message"}.getStr(j["error"].getStr))
    (false, "the model's answer had no text")
  except CatchableError:
    (false, "the model's answer could not be read")

proc aiAsk*(turns: seq[AiTurn]; system: string; done: proc (ok: bool; text: string); maxTokens = 1024): bool =
  ## Sends the conversation; `done` gets the answer (or why there is none). False if the host
  ## refused at once: no model set up, the app lacks the `ai` grant, or too many requests.
  var msgs = newJArray()
  for t in turns: msgs.add %*{"role": t.role, "content": t.text}
  let req = $(%*{"system": system, "messages": msgs, "max_tokens": maxTokens})
  var id = new int32
  let h = onHandler(proc () =
    let n = yFetchBody(id[], 0, 0)
    var body = newString(max(n, 0))
    if n > 0: discard yFetchBody(id[], cast[int32](cast[uint](addr body[0])), n)
    let st = yFetchStatus(id[])
    if st >= 200 and st < 300:
      let (ok, text) = answerText(body)
      done(ok, text)
    elif st > 0:
      let (_, why) = answerText(body)
      done(false, "the model service answered " & $st & (if why.len > 0: ": " & why else: ""))
    else:
      done(false, if body.len > 0: body else: "no answer from the model"))
  id[] = yAi(cast[int32](cast[uint](unsafeAddr req[0])), int32(req.len), h)
  id[] != 0
