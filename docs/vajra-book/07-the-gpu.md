# 7. The GPU

A `kernel` is a Vajra routine that runs on the GPU, once for each point of a grid: each
pixel of an image, each cell of a simulation, each node of a graph. The same kernel also
runs on the CPU, so its results can be checked against each other. All of it is
**planned**, on the foundations noted as **built**.

## 7.1 Kernels

```text
kernel blur(src: GpuImage, dst: var GpuImage, at: Pixel) =
  dst[at] = average(src.around(at, 2px))

kernel step(p: var GpuBuffer[Particle], dt: Duration, i: int) =
  p[i].velocity += gravity * dt
  p[i].position += p[i].velocity * dt

let out = blur.run(over = photo.size)              # one call per pixel
step.run(over = particles.len, dt = 16ms)
```

A kernel may use only what a GPU can do:
- numbers, vectors, matrices, fixed-size arrays, and its buffers and images;
- no strings, no allocation, no exceptions, no calls to the database or the network;
- each point writes only its own place in its outputs (the same rule as the parallel
  `for`, §6.1), so no two points race.
Breaking a rule is a compile error that names it.

## 7.2 How a kernel is made

1. The compiler checks the kernel's rules, on NIF.
2. A plugin writes the kernel as a GLSL compute shader.
3. glslang (wrapped) turns it into SPIR-V, the GPU's standard program format.
4. SDL_shadercross (wrapped) turns SPIR-V into what each system's GPU takes: Metal on
   Apple, DirectX on Windows, Vulkan elsewhere.
5. SDL3's GPU API runs it. SDL3 is wrapped (**built**: `libs/nimsdl3`); its GPU API is
   not bound yet (**planned**).
6. The same kernel is also compiled as a plain Nim routine, for the CPU.

## 7.3 In the sandbox

An app asks for the GPU through the engine, never directly:
- the engine checks every kernel's program before it runs, and adds bounds checks to
  every buffer access;
- a kernel that runs past its time limit is stopped;
- GPU time is metered against the app's grant (§20).

## 7.4 What uses it

Image and video filters; particles and physics (with Jolt, wrapped in `libs/nimjolt`); graph
algorithms over big graphs (§4); the render passes the studio needs (§10, §12); small
models running on the device.

## 7.5 Tests

Planned (each one is a task):
- `blur` on a 1024×1024 image gives the same pixels on the GPU and on the CPU (within one
  step of rounding in each channel).
- A kernel that writes `dst[at + 1]` fails to compile, and the message names the rule.
- A kernel that uses `string` fails to compile.
- A kernel that reads past the end of its buffer is stopped by the engine's bounds check;
  the app gets an error, and the device is unharmed.
- A kernel that loops forever is stopped at its time limit.
- `step` on a million particles runs faster on the GPU than on the CPU, and both give the
  same positions after 100 steps (within rounding).
