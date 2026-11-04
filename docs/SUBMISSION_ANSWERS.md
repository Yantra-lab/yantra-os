# Submission answers (as submitted) — with measured corrections

> **Correction note, 2026-11-05.** This file records what was submitted to the Meta
> Developer Hackathon form. Six figures in the original text were either stale or
> unmeasured; they have been replaced in place with measured values, and the two claims
> that this release tree cannot reproduce (native-engine RAM and cold start) now say so.
> What changed: `minilibc` 21 KB → 23,780 B; app binaries "200–500 KB" → the measured
> 295–2,135 KiB; typewriter "356 KB" → 500,748 B; gallery "214 lines" → 2,755; a
> "410 KB descent" → the DNA helix at 416,112 B (no app named descent exists in the
> release tree); `language.md` "150 KB" → 167,344 B; and the modules were described as
> "WASI" when they deliberately import no WASI at all (32 `env.y_*` functions).
> Every number now in this file is measured — see [VERIFICATION.md](VERIFICATION.md).

# Meta Global AI Developer Hackathon — Submission Answers

## Part 1: Winning Answers for All 22 Hackathon Submission Questions

---

### Project & Team Information

* **1. Team Name:**
`Yantra (यन्त्र)`

* **2. Team Members:**
`Sanskar (संस्कार)` *(IIT Madras)*

* **3. Which track are you submitting to?**
* [x] **Startups Track**

* **4. Which problem statement did you build towards?**
* [x] **Push the Frontier** *(Note: Yantra redefines the foundational application runtime, agent harness, and multi-format rendering stack from first principles).*

* **5. If you're competing for the Most Viral Track, please submit your X post link here to be considered:**
*(Paste your X post URL here — Tip: Pin the 3-minute "Dear Web, We need to talk" programmatic video directly to your X post and tag `@MetaAI`, `@AIatMeta`, and `@cerebral_valley` before submitting!)*

* **6. Project Description:**
**Yantra OS: The Safety of the Web. The Power of Native. Built for Humans and AI Agents.**
For 35 years, the web was built for documents, yet we forced it to run complex applications. Today, opening ten desktop or web apps means running ten redundant copies of Chromium—burning gigabytes of RAM, shipping 200 MB Electron bundles for simple tools, and fighting recursive Virtual DOM tree-diffing and single-threaded JavaScript garbage-collection stalls. Meanwhile, native C++ offers raw speed at the cost of memory-safety hazards, 35,000-line header icebergs, and fragile build toolchains that autonomous AI agents struggle to reason about.

**Yantra** is a next-generation, AI-native application engine and cross-platform operating environment that replaces bloated web/Electron stacks with a hermetic, 3-layer WebAssembly architecture:
1. **Declarative Nim Guest SDK + 23,780 B `minilibc`:** Apps are written in a clean, Python-readable declarative Nim DSL with fine-grained reactive signals. By replacing bloated POSIX libc runtimes with a custom 23,780 B freestanding C stub (`minilibc`), entire 2D/3D applications compile into **`.wasm` modules of 295–2,135 KiB** (measured; nine of the ten are under 565 KiB).
2. **Zero-Copy Binary Wire Protocol:** Sandboxed WebAssembly modules (no WASI, 32 host functions) cannot corrupt host memory or touch unauthorized files; they communicate with the host over a deterministic binary opcode stream.
3. **Sub-2ms Native & Web Host Engine:** Powered by **Wasmtime**, **Meta Yoga 3.1.0** (cached flexbox layout; the cached-path figure was measured on the native engine during development), **Google Skia + HarfBuzz** (2D vector/text), **Google Filament + Jolt** (real-time 3D PBR & physics), **miniaudio**, and **SDL3**—with an identical browser Web Runner fallback.

Built at IIT Madras on just **$150 of Meta Model API credits** by orchestrating **Muse Wonder** and **Muse Spark 1.3 Contributor** through a custom file-based multi-agent noticeboard (`board/`) and an automated pixel-diff verification harness, Yantra delivers sub-100 ms cold starts and 15–25 MB RAM footprints (measured on the native engine during development; the release tree ships no native binary, so these cannot be reproduced from it), hot-swappable live code reloading, and a deterministic `WRITE -> CHECK -> RUN` compiler/visual gate designed to become the fastest native agent harness on earth.

* **7. Public GitHub Repository:**
*(Paste your public GitHub repo URL here)*

* **8. 3-Minute Demo Video:**
*(Paste your YouTube / Loom / X video URL for "The Grant Cut" (2:59.5, exactly under the 3:00 hard stop) film here)*

* **9. Describe your use of Meta products to build the submitted project:**
Yantra is built both **with** Meta’s frontier AI models and **on** Meta’s core layout infrastructure:
1. **Meta Muse Wonder (`muse-wonder`) as Chief Systems Architect:**
Used for high-level systems architecture, designing the zero-copy binary wire protocol (`sdk/core/wire.nim`), solving complex C++/Nim FFI bindings (`skia_shim.cpp`, Filament, Wasmtime), and diagnosing subtle rendering math (such as SVG winding rules, cubic-bezier escapement physics, and Skia clip-rect gradient interpolation in our `029 Carriage Return` typewriter app).

2. **Meta Muse Spark 1.3 Contributor (`muse-spark-1.3-contributor`) as the Autonomous Iterative Engine & App Builder:**
Because Yantra uses a custom Nim SDK and freestanding WASM toolchain that no LLM has seen in pretraining, single-shot generation was impossible. We injected a 167,344 B `language.md` specification and custom SDK skills into context, then built a **file-based multi-agent noticeboard (`.board/`)** to bridge **Muse Wonder** and **Muse Spark 1.3 Contributor**. Muse Wonder wrote architectural specs and pixel-diff probes (`.board/probe/`) to the noticeboard, while Muse Spark 1.3 Contributor executed relentless `WRITE -> COMPILE -> HEADLESS PIXEL-DIFF -> FIX` loops across hundreds of rounds (e.g., round 135 & round 155 in `apps/typewriter/app.nim`) to port C++ libraries to Nim and build showcase apps (`Marlowe 44 Typewriter` at 500,748 B of WebAssembly, the 3D gallery in 2,755 lines of Nim, the DNA helix at 416,112 B, and the programmatic film engine).

3. **Meta Yoga 3.1.0 in the Core Native Host Runtime:**
Meta’s **Yoga 3.1.0** layout engine is embedded directly inside Yantra's native host (`render/native/engine.nim`) to compute flexbox geometry for all UI nodes in **under 0.2 milliseconds** per frame, utilizing `copyStyle` and dirty-subtree caching so unchanged UI branches cost zero layout time.

* **10. Why are Meta's models important to your solution?**
Building an entire operating runtime, a freestanding 23,780 B C library (`minilibc`), C++ bindings for Skia/Filament/Yoga/Wasmtime, multiple 60fps 2D/3D showcase applications, and a programmatic film engine as an IIT Madras student with **only $150 in API credits** would have been economically impossible on any other frontier API.
Meta’s model lineup unlocked a **Two-Tier Asymmetric Agent Architecture** that turned $150 into the output of a 10-person systems engineering team:
* **The Economics of Relentless Verification (`Muse Spark 1.3 Contributor`):** Systems programming and pixel-accurate UI porting require hundreds of compiler and visual-regression iterations (`verify-wasm.mjs` and `refdiff.mjs` comparing rendered frames against reference captures pixel-by-pixel). Because **Muse Spark 1.3 Contributor** is extraordinarily cost-efficient with strong instruction following over a 167,344 B language specification prefix, we could let it loop autonomously through compiler gates and pixel probes without burning through our $150 budget.
* **Deep First-Principles Reasoning (`Muse Wonder`):** Whenever Contributor hit a deep systems wall—such as a WASM `std/math.round` trap, Skia `bDstOut` layer erasure, or SVG object-bounding-box gradient edge cases—**Muse Wonder** stepped in via our shared `.board/` file protocol to derive the exact mathematical fix.
* **Future Roadmap with Meta AI:** Our ultimate goal at Yantra is to replace heavy, 1 GB+ Electron AI coding harnesses (like Codex desktop wrappers or Antigravity) with a **native, 20 MB Yantra Agent Harness** powered by fine-tuned Meta models that can one-shot compile, visually verify, and hot-swap multimodal apps at native speed.

* **11. Provide feedback from your experience using partner technologies:**
**Meta Model API (`Muse Wonder` + `Muse Spark 1.3 Contributor`)** is a phenomenal combination for systems engineering: the price-to-intelligence ratio of `Muse Spark 1.3 Contributor` paired with `Muse Wonder` allowed us to build an entire WASM OS runtime within a $150 student budget.
**Constructive Feedback on `Muse Code` (and an Opportunity for Collaboration):**
1. **Cross-Model Subagent Orchestration:** Currently, `Muse Code` does not support spawning subagents running a different model tier (e.g., having a `Muse Wonder` lead agent automatically dispatch 10 parallel `Muse Spark 1.3 Contributor` subagents for compilation/testing loops). To work around this limitation, we had to engineer our own file-based IPC noticeboard (`.board/`) where two separate chat sessions communicated via shared files and verification scripts. Adding native **Heterogeneous Multi-Model Subagents (Wonder Director -> Contributor Workers)** to `Muse Code` would make it the undisputed #1 agentic harness on the market.
2. **Lightweight Native Harness UI:** Modern AI coding harnesses built on Electron consume 1 GB+ of RAM at idle. Because Yantra renders full flexbox UIs via **Meta Yoga 3.1.0 + Skia** in **15–25 MB of RAM** with sub-100 ms cold start (native-engine measurements, not reproducible from the release tree), we would love to collaborate with the Meta DevTools team to build an ultra-fast, native Yantra frontend and sandboxed execution harness for `Muse Code`.

---

### Ratings & Opinions

* **12. How likely are you to build with Meta Model API?**
* [x] **Very likely**

* **13. How would you describe your overall opinion of Meta Model API?**
* [x] **Very favorable**

* **14. Consent / Agreement Checkbox:**
* [x] *Checked / Accepted*

* **15. How likely are you to recommend the Meta Model API to another developer or engineering team building with LLMs?**
* [x] **`5` (very likely)**

* **16. How likely are you to recommend Muse Code to another developer or engineering team?**
* [x] **`3`** *(Honest, balanced score that aligns with your constructive feedback on missing multi-model subagents while keeping your overall submission positive and credible).*

---

### Developer Feedback & Product Experience

* **17. What was the biggest obstacle your team hit while building this project?**
* [x] **A Muse Code capability we needed was missing (please specify)**
* **Specification text (if prompted):** *"Muse Code currently lacks native support for spawning subagents across different model tiers (e.g., using Muse Wonder as the architect to automatically dispatch and supervise Muse Spark 1.3 Contributor subagents in a compiler/test loop). Additionally, because our custom Nim/Yantra DSL is not in standard pretraining corpora, we had to pass a 167,344 B language.md specification and coordinate Muse Wonder and Muse Spark 1.3 Contributor via a custom file-based noticeboard (.board/)."*

* **18. Compared with other AI models your team has used for the same kind of work, how did Meta’s models perform on this project?**
* [x] **Much better** *(Driven by the unmatched cost-efficiency of Muse Spark 1.3 Contributor for iterative compiler loops paired with Muse Wonder).*

* **19. When your team chooses an AI model or coding tool, what matters most?**
* [x] **Agent abilities such as tool calling and multi-step tasks** *(Or write: `"The ability to iterate autonomously with multi-model subagents on long-horizon compiler/verification loops, backed by high rate limits and low per-token cost."`)*

* **20. What makes it hardest for your team to switch to a different AI model or coding tool?**
* [x] **Our product is tuned to our current model’s behavior and prompts** *(Matches your 167,344 B `language.md` + custom skill files + `.board/` verification harness tuned specifically for Muse Wonder & Contributor).*

* **21. If your team took this project to production, what would most likely stop you from using Meta’s models?**
* [x] **Something else (please specify)**

* **22. Please specify below what would most likely stop you from using Meta's models:**
*"In production, we need the model to one-shot generate idiomatic Yantra Nim DSL and custom binary wire constructs without requiring a 167,344 B in-context `language.md` prompt and multi-turn compiler recovery loops on every task. To take Yantra to production with Meta, we need custom fine-tuning / post-training support (SFT + RL with our compiler/pixel-diff verifier in the loop) on `Muse Spark` so the model natively masters our domain-specific language and codebase."*
