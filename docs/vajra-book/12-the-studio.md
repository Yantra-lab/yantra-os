# 12. The studio: models as providers

Images, video, 3D, speech, voices, music, sound, reading text in pictures, and seeing:
each is done by a model, called from Vajra like any routine. Which model does a job is a
choice the studio makes and records. All of it is **planned**; what it stands on is noted
where it is **built**.

## 12.1 Providers

A provider is a record:

```text
record Provider
  kind: MediaKind                # image, edit, video, mesh, speech, voice, music, sound, ocr, vision, language
  name: string
  runs: Place                    # our GPUs, or an outside service by its host
  takes, gives: seq[string]      # the types it accepts and returns
  costPerCall: INR?
  costPerSecond: INR?
  secondsTypical: Duration
  quality: Json                  # scores per kind of task, from our evaluations and people's picks
```

- An outside service is reached only through `uses network` and `uses secret` (**built**):
  the key is never in the app or the agent.
- A model on our GPUs is a job on the pool (§12.5).

## 12.2 Calls are typed

```text
uses model language, image, video, voice

let hero = image("dawn over Pune, 35mm, haze", size = 2048x1152, seed = 7)
let clean = edit(hero, mask = sky, "make the sky violet")
let clip = video(from = hero, prompt = "slow push in", length = 4s)
let line = voice("Welcome to Yantra.", as = narrator)
let blurb = prose("Two lines for the shop window about {p.name}.", words = 30)
let bowl = mesh("a ceramic bowl, glazed", detail = high)
```

- `prose` returns text. Each other call returns an asset (`Image`, `Clip`, `Sound`, `Mesh`)
  kept as a blob (**built**),
  with how it was made: the provider, the inputs, the seed. So it can be made again,
  varied, or traced to where it came from.
- The same call with the same inputs and seed returns the asset already made, without a
  new call.
- A long call is a flow: the view shows its progress, and its result arrives as a change.
- Every call is checked against a grant (`may call model image, up to ₹300 a day`) and
  metered (§20).

## 12.3 The router

Each call names what it needs, never which model. The router picks the provider by the
quality it measured for that kind of task, the cost and the time. Every result is kept
with the provider that made it, and people's picks and our evaluations update the scores.
A call can still name a provider when the app must have that one.

## 12.4 Composition is code

A film, a product shoot, a scene in a game is a Vajra program: a timeline, cameras, lights,
keyframes (**built**: `keys`), generated assets placed in it. The engine renders it exactly;
then it can pass to a model that keeps the motion and makes it photoreal, using the exact
depth, edges and object masks the engine gives for every frame (§10).

## 12.5 The pool

Our GPUs run the language model and the media models as one pool:
- every call is a job, with a queue, a priority, a budget and a grant;
- a model is loaded where it is needed and unloaded when it is idle;
- GPUs that no call needs train (§ the model plan).

## 12.6 Tests

Planned (each one is a task):
- `image(...)` with the same prompt and seed twice makes one call, and returns the same blob.
- An asset knows its provider, its inputs and its seed.
- A call over its grant's daily limit is refused before any provider is called.
- With two image providers, the router picks the one with the better measured quality for
  the task, unless the call names the other.
- An outside provider's key never appears in a trace, a log or an app's memory.
