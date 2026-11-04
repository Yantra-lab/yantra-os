// qemu CPU-only harness: the shim's GPU block is compiled on Android (guard is
// #ifndef __EMSCRIPTEN__) but this Skia was built with skia_use_gl=false, so the three
// Ganesh-GL factories are supplied here. Each returns null = "no GPU", which the shim
// already handles (yk_gpu_new() -> nullptr). On a device with skia_use_gl=true these
// come from libskia.a instead and this file is not needed.
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/gl/GrGLInterface.h"
#include "include/gpu/ganesh/gl/GrGLDirectContext.h"
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/gl/GrGLBackendSurface.h"

sk_sp<const GrGLInterface> GrGLMakeNativeInterface() { return nullptr; }

namespace GrDirectContexts {
sk_sp<GrDirectContext> MakeGL(sk_sp<const GrGLInterface>) { return nullptr; }
}

namespace GrBackendRenderTargets {
GrBackendRenderTarget MakeGL(int, int, int, int, const GrGLFramebufferInfo&) { return GrBackendRenderTarget(); }
}
