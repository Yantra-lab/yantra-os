// nimfilament: Google Filament (physically based 3D) behind a small C API, built with MSVC into
// yfilament.dll (Filament's Windows release is MSVC-built; the engine itself is MinGW, so the two
// meet at this C boundary). Scenes render offscreen into RGBA pixels that the Yantra engine draws
// like any image — so 3D works in windows, in films (frame-exact) and in PDFs alike.

#include <filament/Engine.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/SwapChain.h>
#include <filament/Viewport.h>
#include <filament/LightManager.h>
#include <filament/IndirectLight.h>
#include <filament/Skybox.h>
#include <backend/PixelBufferDescriptor.h>
#include <gltfio/AssetLoader.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/Animator.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/materials/uberarchive.h>
#include <utils/EntityManager.h>
#include <utils/NameComponentManager.h>
#include <math/vec3.h>
#include <math/mat4.h>
#include <filament/VertexBuffer.h>
#include <filament/IndexBuffer.h>
#include <filament/RenderableManager.h>
#include <filament/TransformManager.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/InstanceBuffer.h>
#include <filament/Options.h>
#include <filament/Texture.h>
#include <filament/ColorGrading.h>
#include <filament/ToneMapper.h>
#include <filament/RenderTarget.h>
#include <filament/TextureSampler.h>
#include <geometry/SurfaceOrientation.h>
#include <filamat/MaterialBuilder.h>
#include <map>
#include <cmath>

#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

using namespace filament;
using namespace filament::gltfio;
using namespace filament::math;

#define YF_API extern "C" __declspec(dllexport)

struct YfScene {
  Engine* engine = nullptr;
  SwapChain* swap = nullptr;
  Renderer* renderer = nullptr;
  Scene* scene = nullptr;
  View* view = nullptr;
  Camera* camera = nullptr;
  utils::Entity cameraEntity, sun;
  IndirectLight* indirect = nullptr;
  MaterialProvider* materials = nullptr;
  AssetLoader* loader = nullptr;
  ResourceLoader* resources = nullptr;
  TextureProvider* stb = nullptr;
  utils::NameComponentManager* names = nullptr;
  FilamentAsset* asset = nullptr;
  int w = 0, h = 0;
  float fov = 45.0f;
  std::string error;
  // scene objects (S3D): meshes, lights and models an app places, by the id yf_obj_* returned
  struct Obj {
    int kind = 0;                       // 0 free, 1 mesh, 2 light, 3 model
    utils::Entity e;
    VertexBuffer* vb = nullptr;
    IndexBuffer* ib = nullptr;
    MaterialInstance* mi = nullptr;     // the first part's material; every part has its own (mis)
    std::vector<MaterialInstance*> mis; // one per part: they differ only in instBase (M3D)
    std::vector<utils::Entity> parts;   // a mesh's renderables under `e`: one, or 64 copies each
    std::vector<InstanceBuffer*> bufs;
    FilamentAsset* asset = nullptr;
    int ninst = 0;
    bool custom = false;                // its material is the app's own shader (it has time and u)
    Texture* maps[4] = {};              // colour, normal, occlusion/roughness/metal, emissive (cached)
    float tile[2] = {1, 1};
    float normalScale = 1;
    Texture* colors = nullptr;          // a colour per instance (owned), 1024 wide
    int alpha = 0;                      // 0 opaque, 1 blended, 2 cut out
    float cutoff = 0.5f;
    Material* shader = nullptr;         // the app's own material, when custom
    // a model's copies (CH1): each has its own animator, skeleton, bone offsets and rest pose
    std::vector<FilamentInstance*> insts;
    std::vector<std::map<std::string, utils::Entity>> joints;   // by node name, per copy
    std::vector<std::map<std::string, mat4f>> boneOff;          // extra local rotation/offset per bone
    std::vector<std::map<std::string, mat4f>> boneRest;         // the bone as it was before any offset
  };
  std::vector<Obj> objs;
  Material* lit[3] = {};               // opaque, transparent, cut out (materials/lit*.mat)
  std::map<std::string, Material*> shaders;
  std::map<std::string, Texture*> textures;   // image maps by file, decoded once (stb, with mipmaps)
  Texture* white = nullptr;                    // the map of a mesh without an image
  Texture* flat = nullptr;                     // the normal map of a mesh without one (straight up)
  Skybox* sky = nullptr;
  ColorGrading* grading = nullptr;
  ToneMapper* toneMapper = nullptr;
  bool ownSun = true;                   // the default sun, until the app places a light
  // cameras that draw into textures (RT1): mirrors, screens, minimaps; maps use them by key
  struct Rt {
    View* view = nullptr;
    Camera* camera = nullptr;
    utils::Entity camEntity;
    RenderTarget* target = nullptr;
    Texture* color = nullptr;
    Texture* depth = nullptr;
    int w = 0, h = 0, bit = 0;          // bit: the layer objects showing it sit in (it does not draw them)
  };
  std::map<std::string, Rt> rts;
};

static const uint8_t YF_LIT[] = {       // the built-in material (materials/lit.mat, by build.bat)
#include "../materials/lit.inc"
};
static const uint8_t YF_LIT_BLEND[] = {
#include "../materials/lit_blend.inc"
};
static const uint8_t YF_LIT_MASK[] = {
#include "../materials/lit_mask.inc"
};

static void noFree(void*, size_t, void*) {}

YF_API void* yf_create(int w, int h) {
  YfScene* s = new YfScene();
  s->w = w; s->h = h;
  s->engine = Engine::create(Engine::Backend::OPENGL);
  if (!s->engine) { delete s; return nullptr; }
  s->swap = s->engine->createSwapChain((uint32_t)w, (uint32_t)h, SwapChain::CONFIG_READABLE);
  s->renderer = s->engine->createRenderer();
  s->scene = s->engine->createScene();
  s->view = s->engine->createView();
  s->cameraEntity = utils::EntityManager::get().create();
  s->camera = s->engine->createCamera(s->cameraEntity);
  s->view->setCamera(s->camera);
  s->view->setScene(s->scene);
  s->view->setViewport({0, 0, (uint32_t)w, (uint32_t)h});
  s->view->setBlendMode(BlendMode::TRANSLUCENT);          // transparent where nothing is drawn
  s->view->setVisibleLayers(0xFF, 0xFF);                   // every layer (cameras into textures skip some: RT1)
  Renderer::ClearOptions clear;
  clear.clearColor = {0, 0, 0, 0};
  clear.clear = true;
  s->renderer->setClearOptions(clear);
  s->camera->setProjection(s->fov, double(w) / double(h), 0.05, 1000.0, Camera::Fov::VERTICAL);
  s->camera->lookAt({0, 1, 4}, {0, 0, 0}, {0, 1, 0});

  s->sun = utils::EntityManager::get().create();
  LightManager::Builder(LightManager::Type::SUN)
      .color({1.0f, 0.97f, 0.92f}).intensity(90000.0f).direction({0.4f, -1.0f, -0.6f})
      .castShadows(true).build(*s->engine, s->sun);
  s->scene->addEntity(s->sun);
  static const float3 sh[9] = {{0.9f, 0.92f, 1.0f}};      // soft sky light from every side
  s->indirect = IndirectLight::Builder().irradiance(1, sh).intensity(25000.0f).build(*s->engine);
  s->scene->setIndirectLight(s->indirect);

  s->materials = createUbershaderProvider(s->engine, UBERARCHIVE_DEFAULT_DATA, UBERARCHIVE_DEFAULT_SIZE);
  s->names = new utils::NameComponentManager(utils::EntityManager::get());   // node names: bones by name (CH1)
  s->loader = AssetLoader::create({s->engine, s->materials, s->names});
  s->stb = createStbProvider(s->engine);
  return s;
}

// Loads a glTF 2.0 model (.glb, or .gltf with its files beside it) and frames the camera on it.
// Returns 1, or 0 with yf_error saying why.
YF_API int yf_load(void* h, const char* path) {
  YfScene* s = (YfScene*)h;
  FILE* f = fopen(path, "rb");
  if (!f) { s->error = std::string("cannot open ") + path; return 0; }
  std::vector<uint8_t> bytes;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  bytes.resize((size_t)n);
  size_t got = fread(bytes.data(), 1, bytes.size(), f);
  fclose(f);
  if (got != bytes.size()) { s->error = "short read"; return 0; }
  if (s->asset) {
    s->scene->removeEntities(s->asset->getEntities(), s->asset->getEntityCount());
    s->loader->destroyAsset(s->asset);
    s->asset = nullptr;
  }
  s->asset = s->loader->createAsset(bytes.data(), (uint32_t)bytes.size());
  if (!s->asset) { s->error = "not a glTF 2.0 model"; return 0; }
  if (!s->resources) {
    ResourceConfiguration cfg = {};
    cfg.engine = s->engine;
    cfg.gltfPath = path;
    cfg.normalizeSkinningWeights = true;
    s->resources = new ResourceLoader(cfg);
    s->resources->addTextureProvider("image/png", s->stb);
    s->resources->addTextureProvider("image/jpeg", s->stb);
  }
  if (!s->resources->loadResources(s->asset)) { s->error = "its buffers or textures did not load"; return 0; }
  s->asset->releaseSourceData();
  s->scene->addEntities(s->asset->getEntities(), s->asset->getEntityCount());
  // frame it: the whole bounding box in view, from the front-right, a little above (3/4 view)
  Aabb box = s->asset->getBoundingBox();
  float3 c = box.center();
  float r = length(box.extent());
  float d = (float)(r / tan(s->fov * 0.5 * 3.14159265 / 180.0) * 1.05);
  s->camera->lookAt({c.x + d * 0.6f, c.y + r * 0.25f, c.z + d * 0.8f}, {c.x, c.y, c.z}, {0, 1, 0});
  return 1;
}

YF_API void yf_camera(void* h, float ex, float ey, float ez, float tx, float ty, float tz, float fov) {
  YfScene* s = (YfScene*)h;
  if (fov > 0) s->fov = fov;
  s->camera->setProjection(s->fov, double(s->w) / double(s->h), 0.05, 1000.0, Camera::Fov::VERTICAL);
  s->camera->lookAt({ex, ey, ez}, {tx, ty, tz}, {0, 1, 0});
}

// Number of animations in the model, and the length of one in seconds.
YF_API int yf_animations(void* h) {
  YfScene* s = (YfScene*)h;
  if (!s->asset) return 0;
  return (int)s->asset->getInstance()->getAnimator()->getAnimationCount();
}

// Renders the scene at time `t` seconds (animation 0 plays, looping) into `rgba` (w*h*4 bytes,
// BGRA, top row first, premultiplied — what the engine's drawPixels takes). 1 when done.
YF_API int yf_render(void* h, double t, uint8_t* rgba) {
  YfScene* s = (YfScene*)h;
  if (s->asset) {
    Animator* anim = s->asset->getInstance()->getAnimator();
    if (anim->getAnimationCount() > 0) {
      float len = anim->getAnimationDuration(0);
      anim->applyAnimation(0, len > 0 ? (float)fmod(t, (double)len) : 0.0f);
      anim->updateBoneMatrices();
    }
  }
  std::vector<uint8_t> tmp((size_t)s->w * s->h * 4);
  bool done = false;
  for (int attempt = 0; attempt < 8 && !done; attempt++) {
    if (!s->renderer->beginFrame(s->swap)) { s->engine->flushAndWait(); continue; }
    for (auto& kv : s->rts) s->renderer->render(kv.second.view);   // cameras into textures first
    s->renderer->render(s->view);
    backend::PixelBufferDescriptor pbd(tmp.data(), tmp.size(), backend::PixelDataFormat::RGBA,
                                       backend::PixelDataType::UBYTE, noFree, nullptr);
    s->renderer->readPixels(0, 0, (uint32_t)s->w, (uint32_t)s->h, std::move(pbd));
    s->renderer->endFrame();
    s->engine->flushAndWait();
    done = true;
  }
  if (!done) { s->error = "the renderer skipped every frame"; return 0; }
  size_t row = (size_t)s->w * 4;                          // Filament reads top row first: RGBA -> BGRA
  for (int y = 0; y < s->h; y++) {
    const uint8_t* src = tmp.data() + (size_t)y * row;
    uint8_t* dst = rgba + (size_t)y * row;
    for (int x = 0; x < s->w; x++) {
      dst[x * 4 + 0] = src[x * 4 + 2]; dst[x * 4 + 1] = src[x * 4 + 1];
      dst[x * 4 + 2] = src[x * 4 + 0]; dst[x * 4 + 3] = src[x * 4 + 3];
    }
  }
  return 1;
}

// --- scene objects (S3D) -----------------------------------------------------------------
// An app's 3D scene is built from objects: meshes (its own vertices, or the engine's shapes),
// lights and glTF models. Each is an id; its transform, material and visibility are set by id
// when they change, so a scene of thousands of objects costs one call per change.

static int newObj(YfScene* s) {
  for (size_t i = 0; i < s->objs.size(); i++) if (s->objs[i].kind == 0) return (int)i;
  s->objs.push_back({});
  return (int)s->objs.size() - 1;
}

static void freeMesh(YfScene* s, YfScene::Obj& o) {
  if (!o.vb) return;
  for (auto p : o.parts) { s->scene->remove(p); s->engine->destroy(p); }
  for (auto b : o.bufs) s->engine->destroy(b);
  o.parts.clear(); o.bufs.clear();
  s->engine->destroy(o.vb); s->engine->destroy(o.ib);
  o.vb = nullptr; o.ib = nullptr;
}

static void freeBytes(void* p, size_t, void*) { free(p); }

static Texture* onePixel(YfScene* s, uint8_t r, uint8_t g, uint8_t b) {
  Texture* t = Texture::Builder().width(1).height(1).levels(1).format(Texture::InternalFormat::RGBA8)
      .sampler(Texture::Sampler::SAMPLER_2D).build(*s->engine);
  uint8_t* px = (uint8_t*)malloc(4); px[0] = r; px[1] = g; px[2] = b; px[3] = 255;
  t->setImage(*s->engine, 0, Texture::PixelBufferDescriptor(px, 4, Texture::Format::RGBA,
              Texture::Type::UBYTE, [](void* p, size_t, void*) { free(p); }));
  return t;
}

// Every map, the tiling, the instance colours and the cut-out on one material instance.
static void applyMaps(YfScene* s, YfScene::Obj& o, MaterialInstance* mi, int part) {
  if (!s->white) s->white = onePixel(s, 255, 255, 255);   // no image: the colour as is
  if (!s->flat) s->flat = onePixel(s, 128, 128, 255);     // no normal map: straight up
  TextureSampler smp(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR, TextureSampler::MagFilter::LINEAR,
                     TextureSampler::WrapMode::REPEAT);
  smp.setAnisotropy(8);
  TextureSampler exact(TextureSampler::MagFilter::NEAREST);
  mi->setParameter("map", o.maps[0] ? o.maps[0] : s->white, smp);
  mi->setParameter("normalMap", o.maps[1] ? o.maps[1] : s->flat, smp);
  mi->setParameter("ormMap", o.maps[2] ? o.maps[2] : s->white, smp);
  mi->setParameter("emissiveMap", o.maps[3] ? o.maps[3] : s->white, smp);
  mi->setParameter("tiling", float2{o.tile[0], o.tile[1]});
  mi->setParameter("normalScale", o.normalScale);
  mi->setParameter("instTex", o.colors ? o.colors : s->white, exact);
  mi->setParameter("instOn", o.colors ? 1.0f : 0.0f);
  int per = (int)s->engine->getMaxAutomaticInstances();
  mi->setParameter("instBase", (float)(part * per));
  if (o.alpha == 2) mi->setMaskThreshold(o.cutoff);
}

static void applyAll(YfScene* s, YfScene::Obj& o) {
  for (size_t k = 0; k < o.mis.size(); k++) applyMaps(s, o, o.mis[k], (int)k);
}

static Material* litFor(YfScene* s, int alpha) {
  if (!s->lit[alpha]) {
    const uint8_t* pkg = alpha == 1 ? YF_LIT_BLEND : alpha == 2 ? YF_LIT_MASK : YF_LIT;
    size_t n = alpha == 1 ? sizeof(YF_LIT_BLEND) : alpha == 2 ? sizeof(YF_LIT_MASK) : sizeof(YF_LIT);
    s->lit[alpha] = Material::Builder().package(pkg, n).build(*s->engine);
  }
  return s->lit[alpha];
}

// One material instance per part, of `m`, with o.mi's colour and finish carried over.
static void remat(YfScene* s, YfScene::Obj& o, Material* m) {
  float4 base = {0.8f, 0.8f, 0.8f, 1.0f};
  float metal = 0, rough = 0.6f;
  float3 glow = {0, 0, 0};
  if (o.mi) {
    base = o.mi->getParameter<float4>("baseColor");
    metal = o.mi->getParameter<float>("metallic");
    rough = o.mi->getParameter<float>("roughness");
    glow = o.mi->getParameter<float3>("emissive");
  }
  auto& rm = s->engine->getRenderableManager();
  std::vector<MaterialInstance*> old = o.mis;
  o.mis.clear();
  size_t n = o.parts.empty() ? 1 : o.parts.size();
  for (size_t k = 0; k < n; k++) {
    MaterialInstance* mi = m->createInstance();
    mi->setParameter("baseColor", base);
    mi->setParameter("metallic", metal);
    mi->setParameter("roughness", rough);
    mi->setParameter("emissive", glow);
    applyMaps(s, o, mi, (int)k);
    if (k < o.parts.size()) rm.setMaterialInstanceAt(rm.getInstance(o.parts[k]), 0, mi);
    o.mis.push_back(mi);
  }
  o.mi = o.mis[0];
  for (auto mi : old) s->engine->destroy(mi);
}

// Mesh `id` (a new one if `id` is not a mesh): `nv` vertices of 8 floats (position, normal, uv) and
// `ni` triangle indices; `ninst` > 1 draws it that many times (yf_obj_instances places them).
// A rebuilt mesh keeps its transform and material.
YF_API int yf_obj_mesh(void* h, int id, const float* v, int nv, const uint32_t* idx, int ni, int ninst) {
  YfScene* s = (YfScene*)h;
  if (nv <= 0 || ni <= 0) return -1;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 1) { id = newObj(s); s->objs[id].kind = 1; }
  YfScene::Obj& o = s->objs[id];
  if (!o.mi) remat(s, o, litFor(s, o.alpha));
  auto& tm = s->engine->getTransformManager();
  freeMesh(s, o);
  if (o.e.isNull()) { o.e = utils::EntityManager::get().create(); tm.create(o.e); }
  if (ninst < 1) ninst = 1;
  float3* pos = (float3*)malloc(sizeof(float3) * nv);
  float3* nrm = (float3*)malloc(sizeof(float3) * nv);
  float2* uv = (float2*)malloc(sizeof(float2) * nv);
  float3 lo = {1e30f, 1e30f, 1e30f}, hi = {-1e30f, -1e30f, -1e30f};
  for (int i = 0; i < nv; i++) {
    pos[i] = {v[i * 8], v[i * 8 + 1], v[i * 8 + 2]};
    nrm[i] = {v[i * 8 + 3], v[i * 8 + 4], v[i * 8 + 5]};
    uv[i] = {v[i * 8 + 6], v[i * 8 + 7]};
    lo = min(lo, pos[i]); hi = max(hi, pos[i]);
  }
  short4* tan = (short4*)malloc(sizeof(short4) * nv);
  // tangents that follow the uvs (normal maps lean the right way); normals alone if not triangles
  auto* so = ni % 3 == 0
    ? geometry::SurfaceOrientation::Builder().vertexCount(nv).normals(nrm).uvs(uv).positions(pos)
        .triangleCount(ni / 3).triangles((const uint3*)idx).build()
    : geometry::SurfaceOrientation::Builder().vertexCount(nv).normals(nrm).build();
  so->getQuats(tan, nv);
  delete so;
  free(nrm);
  uint32_t* ix = (uint32_t*)malloc(sizeof(uint32_t) * ni);
  memcpy(ix, idx, sizeof(uint32_t) * ni);
  o.vb = VertexBuffer::Builder().vertexCount(nv).bufferCount(3)
      .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3)
      .attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::SHORT4)
      .normalized(VertexAttribute::TANGENTS)
      .attribute(VertexAttribute::UV0, 2, VertexBuffer::AttributeType::FLOAT2).build(*s->engine);
  o.vb->setBufferAt(*s->engine, 0, VertexBuffer::BufferDescriptor(pos, sizeof(float3) * nv, freeBytes));
  o.vb->setBufferAt(*s->engine, 1, VertexBuffer::BufferDescriptor(tan, sizeof(short4) * nv, freeBytes));
  o.vb->setBufferAt(*s->engine, 2, VertexBuffer::BufferDescriptor(uv, sizeof(float2) * nv, freeBytes));
  o.ib = IndexBuffer::Builder().indexCount(ni).bufferType(IndexBuffer::IndexType::UINT).build(*s->engine);
  o.ib->setBuffer(*s->engine, IndexBuffer::BufferDescriptor(ix, sizeof(uint32_t) * ni, freeBytes));
  o.ninst = ninst;
  // Filament instances at most getMaxAutomaticInstances() (64) copies per renderable: more
  // copies are split over several renderables, all under the object's own transform
  int per = (int)s->engine->getMaxAutomaticInstances();
  for (int first = 0; first < ninst; first += per) {
    int n = ninst - first < per ? ninst - first : per;
    utils::Entity p = utils::EntityManager::get().create();
    RenderableManager::Builder rb(1);
    rb.boundingBox(Box().set(lo, hi)).material(0, o.mis[0])
      .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, o.vb, o.ib, 0, ni)
      .castShadows(true).receiveShadows(true);
    if (ninst > 1) {
      InstanceBuffer* b = InstanceBuffer::Builder(n).build(*s->engine);
      rb.instances(n, b).culling(false);
      o.bufs.push_back(b);
    }
    rb.build(*s->engine, p);
    tm.create(p, tm.getInstance(o.e));
    o.parts.push_back(p);
    s->scene->addEntity(p);
  }
  remat(s, o, o.custom && o.shader ? o.shader : litFor(s, o.alpha));   // one material per part
  return id;
}

// The app's own shader for mesh `id` (filamat compiles it at run time, once per source):
// `frag` is the body of material(): it may set any of material.baseColor, roughness,
// metallic, emissive, normal... after the mesh's own values are in; `vert` (optional) the
// body of materialVertex(), e.g. moving material.worldPosition (waves). Both see
// materialParams.baseColor/metallic/roughness/emissive (the mesh's props), .time (seconds)
// and .u[0..3] (vec4s the app sets). `blend` 1: transparent. 1 when it compiled; else 0 and
// yf_error says so (the mesh keeps its old material).
YF_API int yf_obj_shader(void* h, int id, const char* frag, const char* vert, int blend, int unlit) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 1) return 0;
  YfScene::Obj& o = s->objs[id];
  std::string key = std::string(frag) + "\x01" + vert + "\x01" + (blend ? "b" : "o") + (unlit ? "u" : "l");
  Material* m = nullptr;
  auto it = s->shaders.find(key);
  if (it != s->shaders.end()) m = it->second;
  else {
    static bool ready = false;
    if (!ready) { filamat::MaterialBuilder::init(); ready = true; }
    filamat::MaterialBuilder b;
    std::string fbody = std::string("void material(inout MaterialInputs material) {\n"
        "    vec2 uv = getUV0() * materialParams.tiling;\n"
        "    vec3 nn = texture(materialParams_normalMap, uv).xyz * 2.0 - 1.0;\n"
        "    nn.xy *= materialParams.normalScale;\n"
        "    material.normal = normalize(nn);\n"
        "    prepareMaterial(material);\n"
        "    vec4 tt = texture(materialParams_map, uv);\n"
        "    vec4 ic = variable_instColor;\n"
        "    material.baseColor = materialParams.baseColor * vec4(tt.rgb * tt.a, tt.a) * vec4(ic.rgb * ic.a, ic.a);\n") +
        (unlit ? "" : "    vec4 orm = texture(materialParams_ormMap, uv);\n"
                      "    material.metallic = materialParams.metallic * orm.b;\n"
                      "    material.roughness = materialParams.roughness * orm.g;\n"
                      "    material.ambientOcclusion = orm.r;\n") +
        "    material.emissive = vec4(materialParams.emissive * texture(materialParams_emissiveMap, uv).rgb, 0.0);\n" +
        frag + "\n}\n";
    std::string vbody = std::string("void materialVertex(inout MaterialVertexInputs material) {\n"
        "    if (materialParams.instOn > 0.5) {\n"
        "        int i = int(materialParams.instBase) + int(getInstanceIndex());\n"
        "        material.instColor = texelFetch(materialParams_instTex, ivec2(i % 1024, i / 1024), 0);\n"
        "    } else { material.instColor = vec4(1.0); }\n") + vert + "\n}\n";
    using UT = filamat::MaterialBuilder::UniformType;
    b.name("app").targetApi(filamat::MaterialBuilder::TargetApi::OPENGL)
     .platform(filamat::MaterialBuilder::Platform::DESKTOP)
     .shading(unlit ? Shading::UNLIT : Shading::LIT)
     .require(VertexAttribute::TANGENTS).require(VertexAttribute::UV0)
     .parameter("map", filamat::MaterialBuilder::SamplerType::SAMPLER_2D)
     .parameter("tiling", UT::FLOAT2)
     .parameter("normalMap", filamat::MaterialBuilder::SamplerType::SAMPLER_2D)
     .parameter("normalScale", UT::FLOAT)
     .parameter("ormMap", filamat::MaterialBuilder::SamplerType::SAMPLER_2D)
     .parameter("emissiveMap", filamat::MaterialBuilder::SamplerType::SAMPLER_2D)
     .parameter("instTex", filamat::MaterialBuilder::SamplerType::SAMPLER_2D)
     .parameter("instOn", UT::FLOAT).parameter("instBase", UT::FLOAT)
     .variable(filamat::MaterialBuilder::Variable::CUSTOM0, "instColor")
     .instanced(true)
     .parameter("baseColor", UT::FLOAT4).parameter("metallic", UT::FLOAT).parameter("roughness", UT::FLOAT)
     .parameter("emissive", UT::FLOAT3).parameter("time", UT::FLOAT).parameter("u", 4, UT::FLOAT4)
     .doubleSided(true)
     .blending(blend ? BlendingMode::TRANSPARENT : BlendingMode::OPAQUE)
     .material(fbody.c_str())
     .materialVertex(vbody.c_str());
    filamat::Package pkg = b.build(s->engine->getJobSystem());
    if (!pkg.isValid()) { s->error = "the shader did not compile (the log has the line)"; return 0; }
    m = Material::Builder().package(pkg.getData(), pkg.getSize()).build(*s->engine);
    if (!m) { s->error = "the shader compiled but did not load"; return 0; }
    s->shaders[key] = m;
  }
  o.custom = true;
  o.shader = m;
  remat(s, o, m);
  for (auto mi : o.mis) {
    mi->setParameter("time", 0.0f);
    float4 zero[4] = {};
    mi->setParameter("u", zero, 4);
  }
  return 1;
}

// A texture from RGBA pixels (not premultiplied, top row first) under `key`: made, or its pixels
// replaced when the size is the same; mipmapped. A layer or a buffer the app draws becomes a map.
YF_API int yf_tex_pixels(void* h, const char* key, const uint8_t* rgba, int w, int ht, int srgb) {
  YfScene* s = (YfScene*)h;
  if (!key || !rgba || w <= 0 || ht <= 0) return 0;
  Texture* t = nullptr;
  auto it = s->textures.find(key);
  if (it != s->textures.end() && (int)it->second->getWidth() == w && (int)it->second->getHeight() == ht) t = it->second;
  else {
    if (it != s->textures.end()) { s->engine->destroy(it->second); s->textures.erase(it); }
    int levels = 1;
    for (int m = w > ht ? w : ht; m > 1; m >>= 1) levels++;
    t = Texture::Builder().width(w).height(ht).levels(levels)
        .format(srgb ? Texture::InternalFormat::SRGB8_A8 : Texture::InternalFormat::RGBA8)
        .usage(Texture::Usage::DEFAULT | Texture::Usage::GEN_MIPMAPPABLE)
        .sampler(Texture::Sampler::SAMPLER_2D).build(*s->engine);
    s->textures[key] = t;
  }
  size_t n = (size_t)w * ht * 4;
  uint8_t* px = (uint8_t*)malloc(n);
  memcpy(px, rgba, n);
  t->setImage(*s->engine, 0, Texture::PixelBufferDescriptor(px, n, Texture::Format::RGBA, Texture::Type::UBYTE,
              [](void* p, size_t, void*) { free(p); }));
  t->generateMipmaps(*s->engine);
  return 1;
}

// Mesh `id`'s map in `slot` (0 colour, 1 normal, 2 occlusion/roughness/metal, 3 emissive): a png
// or jpeg file, or a key yf_tex_pixels made; "" none. `tu` x `tv` repeats it across uv 0..1.
// Files are decoded once, with mipmaps. 0 with yf_error if it is not an image.
YF_API int yf_obj_map(void* h, int id, int slot, const char* path, float tu, float tv) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || !s->objs[id].mi || slot < 0 || slot > 3) return 0;
  YfScene::Obj& o = s->objs[id];
  Texture* t = nullptr;
  if (path && path[0]) {
    auto it = s->textures.find(path);
    if (it != s->textures.end()) t = it->second;
    else {
      FILE* f = fopen(path, "rb");
      if (!f) { s->error = std::string("cannot open ") + path; return 0; }
      std::vector<uint8_t> bytes;
      fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
      bytes.resize((size_t)n);
      size_t got = fread(bytes.data(), 1, bytes.size(), f);
      fclose(f);
      if (got != bytes.size()) { s->error = "short read"; return 0; }
      std::string p(path);
      const char* mime = (p.size() > 4 && (p.substr(p.size() - 4) == ".jpg" || p.substr(p.size() - 5) == ".jpeg"))
                         ? "image/jpeg" : "image/png";
      t = s->stb->pushTexture(bytes.data(), bytes.size(), mime,
                              slot == 0 || slot == 3 ? TextureProvider::TextureFlags::sRGB : TextureProvider::TextureFlags::NONE);
      if (!t) { s->error = std::string("not an image: ") + s->stb->getPushMessage(); return 0; }
      s->stb->waitForCompletion();
      s->stb->updateQueue();
      while (s->stb->popTexture()) {}
      s->textures[path] = t;
    }
  }
  o.maps[slot] = t;
  if (slot == 0) { o.tile[0] = tu; o.tile[1] = tv; }
  applyAll(s, o);
  return 1;
}

// Kept for older callers: the colour map.
YF_API int yf_obj_texture(void* h, int id, const char* path, float tu, float tv) { return yf_obj_map(h, id, 0, path, tu, tv); }

// How strong the normal map is (1 as drawn), and how the mesh uses alpha: 0 opaque, 1 blended
// (glass, water), 2 cut out where alpha < cutoff (leaves, fences).
YF_API void yf_obj_surface(void* h, int id, float normalScale, int alpha, float cutoff) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || !s->objs[id].mi) return;
  YfScene::Obj& o = s->objs[id];
  o.normalScale = normalScale;
  o.cutoff = cutoff;
  if (alpha < 0 || alpha > 2) alpha = 0;
  if (alpha != o.alpha && !o.custom) { o.alpha = alpha; remat(s, o, litFor(s, alpha)); }
  else { o.alpha = alpha; applyAll(s, o); }
}

// A colour per instance of mesh `id`: `n` RGBA bytes quads (not premultiplied), in placement order.
YF_API void yf_obj_colors(void* h, int id, const uint8_t* rgba, int n) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || !s->objs[id].mi) return;
  YfScene::Obj& o = s->objs[id];
  Texture* old = nullptr;               // replaced only after the materials let go of it
  if (rgba && n > 0) {
    int w = 1024, ht = (n + 1023) / 1024;
    if (!o.colors || (int)o.colors->getHeight() != ht) {   // same size: new pixels, same texture
      old = o.colors;
      o.colors = Texture::Builder().width(w).height(ht).levels(1).format(Texture::InternalFormat::SRGB8_A8)   // app colours are sRGB
          .sampler(Texture::Sampler::SAMPLER_2D).build(*s->engine);
    }
    size_t bytes = (size_t)w * ht * 4;
    uint8_t* px = (uint8_t*)calloc(bytes, 1);
    memcpy(px, rgba, (size_t)n * 4);
    o.colors->setImage(*s->engine, 0, Texture::PixelBufferDescriptor(px, bytes, Texture::Format::RGBA,
                       Texture::Type::UBYTE, [](void* p, size_t, void*) { free(p); }));
  } else { old = o.colors; o.colors = nullptr; }
  applyAll(s, o);
  if (old) s->engine->destroy(old);
}

// Shader inputs: the time in seconds, and 16 floats (u[0..3]) the app chose.
YF_API void yf_obj_uniforms(void* h, int id, float time, const float* u16) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || !s->objs[id].custom) return;
  for (MaterialInstance* mi : s->objs[id].mis) {
    mi->setParameter("time", time);
    if (u16) mi->setParameter("u", (const float4*)u16, 4);
  }
}

// Places mesh `id`'s instances: `m` holds `n` column-major 4x4 matrices.
YF_API void yf_obj_instances(void* h, int id, const float* m, int n) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].bufs.empty()) return;
  YfScene::Obj& o = s->objs[id];
  if (n > o.ninst) n = o.ninst;
  int per = (int)s->engine->getMaxAutomaticInstances();
  for (size_t k = 0; k < o.bufs.size() && (int)k * per < n; k++) {
    int count = n - (int)k * per < per ? n - (int)k * per : per;
    o.bufs[k]->setLocalTransforms((const mat4f*)(m + (size_t)k * per * 16), (size_t)count, 0);
  }
}

// Colour 0..1 (straight alpha), metal and rough 0..1, glow colour (can exceed 1: bloom).
YF_API void yf_obj_material(void* h, int id, float r, float g, float b, float a, float metal, float rough,
                            float er, float eg, float eb) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || !s->objs[id].mi) return;
  for (MaterialInstance* mi : s->objs[id].mis) {
    mi->setParameter("baseColor", float4{r * a, g * a, b * a, a});
    mi->setParameter("metallic", metal);
    mi->setParameter("roughness", rough);
    mi->setParameter("emissive", float3{er, eg, eb});
  }
}

// Object `id`'s column-major 4x4 local-to-world matrix.
YF_API void yf_obj_transform(void* h, int id, const float* m) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind == 0) return;
  YfScene::Obj& o = s->objs[id];
  utils::Entity e = o.kind == 3 ? o.insts[0]->getRoot() : o.e;
  auto& tm = s->engine->getTransformManager();
  if (!tm.hasComponent(e)) tm.create(e);
  mat4f mm;
  memcpy(&mm, m, sizeof(float) * 16);
  tm.setTransform(tm.getInstance(e), mm);
}

YF_API void yf_obj_visible(void* h, int id, int on) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind == 0) return;
  YfScene::Obj& o = s->objs[id];
  if (o.kind == 3) {
    if (on) s->scene->addEntities(o.asset->getEntities(), o.asset->getEntityCount());
    else s->scene->removeEntities(o.asset->getEntities(), o.asset->getEntityCount());
  } else if (o.kind == 1) {
    for (auto p : o.parts) { if (on) s->scene->addEntity(p); else s->scene->remove(p); }
  } else if (on) s->scene->addEntity(o.e);
  else s->scene->remove(o.e);
}

// A light (replacing light `id` if it is one): type 0 sun, 1 point, 2 spot; colour 0..1;
// intensity (lux for a sun, lumens otherwise); position, direction; falloff metres.
// The first light an app places replaces the default sun.
YF_API int yf_obj_light(void* h, int id, int type, float r, float g, float b, float intensity,
                        float px, float py, float pz, float dx, float dy, float dz, float falloff, int shadows) {
  YfScene* s = (YfScene*)h;
  if (s->ownSun) { s->scene->remove(s->sun); s->ownSun = false; }
  if (id >= 0 && id < (int)s->objs.size() && s->objs[id].kind == 2) {
    s->scene->remove(s->objs[id].e);
    s->engine->destroy(s->objs[id].e);
  } else { id = newObj(s); s->objs[id].kind = 2; }
  YfScene::Obj& o = s->objs[id];
  o.e = utils::EntityManager::get().create();
  auto t = type == 1 ? LightManager::Type::POINT : type == 2 ? LightManager::Type::SPOT : LightManager::Type::SUN;
  LightManager::ShadowOptions so;
  so.shadowCascades = 4;              // cascaded shadow maps: sharp near, still there far away
  so.mapSize = 2048;
  LightManager::Builder lb(t);
  lb.color({r, g, b}).intensity(intensity).position({px, py, pz}).direction({dx, dy, dz})
    .falloff(falloff > 0 ? falloff : 10.0f).castShadows(shadows != 0).shadowOptions(so);
  if (type == 2) lb.spotLightCone(0.3f, 0.6f);
  lb.build(*s->engine, o.e);
  s->scene->addEntity(o.e);
  return id;
}

// A glTF model as a scene object, with its own transform. -1 with yf_error saying why.
// A glTF model with `count` copies (a crowd shares its meshes and textures; each copy has its own
// transform, animation and skeleton). -1 with yf_error saying why.
YF_API int yf_obj_model_n(void* h, const char* path, int count) {
  YfScene* s = (YfScene*)h;
  if (count < 1) count = 1;
  FILE* f = fopen(path, "rb");
  if (!f) { s->error = std::string("cannot open ") + path; return -1; }
  std::vector<uint8_t> bytes;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  bytes.resize((size_t)n);
  size_t got = fread(bytes.data(), 1, bytes.size(), f);
  fclose(f);
  if (got != bytes.size()) { s->error = "short read"; return -1; }
  std::vector<FilamentInstance*> insts((size_t)count);
  FilamentAsset* a = s->loader->createInstancedAsset(bytes.data(), (uint32_t)bytes.size(), insts.data(), (size_t)count);
  if (!a) { s->error = "not a glTF 2.0 model"; return -1; }
  ResourceConfiguration cfg = {};
  cfg.engine = s->engine;
  cfg.gltfPath = path;
  cfg.normalizeSkinningWeights = true;
  ResourceLoader res(cfg);
  res.addTextureProvider("image/png", s->stb);
  res.addTextureProvider("image/jpeg", s->stb);
  if (!res.loadResources(a)) { s->loader->destroyAsset(a); s->error = "its buffers or textures did not load"; return -1; }
  a->releaseSourceData();
  s->scene->addEntities(a->getEntities(), a->getEntityCount());
  int id = newObj(s);
  YfScene::Obj& o = s->objs[id];
  o.kind = 3;
  o.asset = a;
  o.insts = insts;
  o.joints.resize(insts.size());
  o.boneOff.resize(insts.size());
  o.boneRest.resize(insts.size());
  for (size_t k = 0; k < insts.size(); k++)
    for (size_t i = 0; i < insts[k]->getEntityCount(); i++) {
      utils::Entity e = insts[k]->getEntities()[i];
      const char* nm = a->getName(e);
      if (nm) o.joints[k][nm] = e;
    }
  return id;
}

YF_API int yf_obj_model(void* h, const char* path) { return yf_obj_model_n(h, path, 1); }

static YfScene::Obj* modelAt(YfScene* s, int id, int k) {
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 3) return nullptr;
  YfScene::Obj& o = s->objs[id];
  return k >= 0 && k < (int)o.insts.size() ? &o : nullptr;
}

YF_API int yf_obj_copies(void* h, int id) {
  YfScene* s = (YfScene*)h;
  return id >= 0 && id < (int)s->objs.size() && s->objs[id].kind == 3 ? (int)s->objs[id].insts.size() : 0;
}

// Copy `k` of model `id`: its column-major 4x4 local-to-world matrix.
YF_API void yf_obj_copy_transform(void* h, int id, int k, const float* m) {
  YfScene* s = (YfScene*)h;
  YfScene::Obj* o = modelAt(s, id, k);
  if (!o) return;
  auto& tm = s->engine->getTransformManager();
  utils::Entity e = o->insts[k]->getRoot();
  if (!tm.hasComponent(e)) tm.create(e);
  mat4f mm;
  memcpy(&mm, m, sizeof(float) * 16);
  tm.setTransform(tm.getInstance(e), mm);
}

// The index of the clip called `name` (-1 if the model has none).
YF_API int yf_obj_clip(void* h, int id, const char* name) {
  YfScene* s = (YfScene*)h;
  YfScene::Obj* o = modelAt(s, id, 0);
  if (!o || !name) return -1;
  Animator* an = o->insts[0]->getAnimator();
  for (size_t i = 0; i < an->getAnimationCount(); i++)
    if (strcmp(an->getAnimationName(i), name) == 0) return (int)i;
  return -1;
}

// Copy `k`'s pose: clip `a` at `ta` seconds (looping; -1 none), blended from clip `b` at `tb` by
// alpha (0 all b, 1 all a); then the bone offsets on top; then the skin follows.
YF_API void yf_obj_pose(void* h, int id, int k, int a, double ta, int b, double tb, float alpha) {
  YfScene* s = (YfScene*)h;
  YfScene::Obj* o = modelAt(s, id, k);
  if (!o) return;
  Animator* an = o->insts[k]->getAnimator();
  int n = (int)an->getAnimationCount();
  auto& tm = s->engine->getTransformManager();
  auto loop = [&](int i, double t) {
    float len = an->getAnimationDuration((size_t)i);
    return len > 0 ? (float)fmod(t, (double)len) : 0.0f;
  };
  if (a >= 0 && a < n) {
    an->applyAnimation((size_t)a, loop(a, ta));
    if (b >= 0 && b < n && b != a && alpha < 1) an->applyCrossFade((size_t)b, loop(b, tb), alpha < 0 ? 0 : alpha);
  } else {
    for (auto& kv : o->boneRest[k]) {           // no clip: back to rest before the offsets
      auto j = o->joints[k].find(kv.first);
      if (j != o->joints[k].end()) tm.setTransform(tm.getInstance(j->second), kv.second);
    }
  }
  for (auto& kv : o->boneOff[k]) {
    auto j = o->joints[k].find(kv.first);
    if (j == o->joints[k].end()) continue;
    auto ti = tm.getInstance(j->second);
    tm.setTransform(ti, tm.getTransform(ti) * kv.second);
  }
  an->updateBoneMatrices();
}

// An offset for bone `bone` of copy `k` (k < 0: every copy): a rotation (quaternion x, y, z, w)
// and a move, on top of its animation (aiming a head, reaching a hand). All zero: none.
YF_API int yf_obj_bone(void* h, int id, int k, const char* bone, float qx, float qy, float qz, float qw,
                       float px, float py, float pz) {
  YfScene* s = (YfScene*)h;
  if (!modelAt(s, id, 0) || !bone) return 0;
  YfScene::Obj& o = s->objs[id];
  auto& tm = s->engine->getTransformManager();
  int found = 0;
  for (int c = 0; c < (int)o.insts.size(); c++) {
    if (k >= 0 && c != k) continue;
    auto j = o.joints[c].find(bone);
    if (j == o.joints[c].end()) continue;
    found = 1;
    if (!o.boneRest[c].count(bone)) o.boneRest[c][bone] = tm.getTransform(tm.getInstance(j->second));
    if (qx == 0 && qy == 0 && qz == 0 && qw == 0 && px == 0 && py == 0 && pz == 0) { o.boneOff[c].erase(bone); continue; }
    mat4f m = mat4f(quatf(qw, qx, qy, qz));
    m[3] = float4{px, py, pz, 1};
    o.boneOff[c][bone] = m;
  }
  return found;
}

// Where bone `bone` of copy `k` is in the world now (after the last pose). 0 if no such bone.
YF_API int yf_obj_bone_world(void* h, int id, int k, const char* bone, float* out) {
  YfScene* s = (YfScene*)h;
  YfScene::Obj* o = modelAt(s, id, k);
  if (!o || !bone) return 0;
  auto j = o->joints[k].find(bone);
  if (j == o->joints[k].end()) return 0;
  auto& tm = s->engine->getTransformManager();
  mat4f w = tm.getWorldTransform(tm.getInstance(j->second));
  out[0] = w[3][0]; out[1] = w[3][1]; out[2] = w[3][2];
  return 1;
}

// Model `id` at `t` seconds of its animation `which` (looping).
YF_API void yf_obj_animate(void* h, int id, int which, double t) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 3) return;
  Animator* anim = s->objs[id].insts[0]->getAnimator();
  if (which < 0 || (int)anim->getAnimationCount() <= which) return;
  float len = anim->getAnimationDuration(which);
  anim->applyAnimation(which, len > 0 ? (float)fmod(t, (double)len) : 0.0f);
  anim->updateBoneMatrices();
}

// 1 if model `id` has an animation `which` (it plays, so the view keeps repainting).
YF_API int yf_obj_has_animation(void* h, int id, int which) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 3 || which < 0) return 0;
  return (int)s->objs[id].insts[0]->getAnimator()->getAnimationCount() > which ? 1 : 0;
}

YF_API void yf_obj_remove(void* h, int id) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size()) return;
  YfScene::Obj& o = s->objs[id];
  if (o.kind == 1) {
    freeMesh(s, o);
    for (auto mi : o.mis) s->engine->destroy(mi);
    if (o.colors) s->engine->destroy(o.colors);
    if (!o.e.isNull()) { s->engine->getTransformManager().destroy(o.e); utils::EntityManager::get().destroy(o.e); }
  }
  else if (o.kind == 2) { s->scene->remove(o.e); s->engine->destroy(o.e); }
  else if (o.kind == 3) { s->scene->removeEntities(o.asset->getEntities(), o.asset->getEntityCount()); s->loader->destroyAsset(o.asset); }
  o = YfScene::Obj();
}

// The world around the objects: sky colour (sa 0: transparent), fog density and colour, how
// bright the sky's soft light is (< 0: unchanged), and the finish: shadows, ambient
// occlusion, bloom strength (0 off), MSAA samples (1 off; FXAA always).
YF_API void yf_env(void* h, float sr, float sg, float sb, float sa, float fogDensity, float fr, float fg, float fb,
                   float ambient, int shadows, int ssao, float bloom, int msaa) {
  YfScene* s = (YfScene*)h;
  if (s->sky) { s->scene->setSkybox(nullptr); s->engine->destroy(s->sky); s->sky = nullptr; }
  if (sa > 0) {
    s->sky = Skybox::Builder().color({sr, sg, sb, 1.0f}).build(*s->engine);
    s->scene->setSkybox(s->sky);
  }
  View::FogOptions fog;
  fog.enabled = fogDensity > 0;
  fog.density = fogDensity;
  fog.color = {fr, fg, fb};
  fog.distance = 0.0f;
  View::FogOptions was = s->view->getFogOptions();      // height fog (yf_post) stays
  fog.height = was.height;
  fog.heightFalloff = was.heightFalloff;
  s->view->setFogOptions(fog);
  if (ambient >= 0) s->indirect->setIntensity(ambient);
  s->view->setShadowingEnabled(shadows != 0);
  View::AmbientOcclusionOptions ao;
  ao.enabled = ssao != 0;
  s->view->setAmbientOcclusionOptions(ao);
  View::BloomOptions bl;
  bl.enabled = bloom > 0;
  bl.strength = bloom;
  s->view->setBloomOptions(bl);
  View::MultiSampleAntiAliasingOptions ms;
  ms.enabled = msaa > 1;
  ms.sampleCount = (uint8_t)(msaa > 1 ? msaa : 1);
  s->view->setMultiSampleAntiAliasingOptions(ms);
  s->view->setAntiAliasing(View::AntiAliasing::FXAA);
}

// The finish, like a film camera's (LK1): temporal anti-aliasing, depth of field (focus at `dofFocus`
// metres, `dofBlur` how strongly; 0 off), screen-space reflections, vignette 0..1, and the grade:
// exposure (EV stops), contrast and saturation (1 as is), tone mapper (0 ACES, 1 filmic, 2 AgX,
// 3 neutral, 4 linear); height fog (fog thins with height: fogHeight where it starts, falloff).
YF_API void yf_post(void* h, int taa, float dofFocus, float dofBlur, int ssr, float vignette, float exposure,
                    float contrast, float saturation, int toneMap, float fogHeight, float fogFalloff) {
  YfScene* s = (YfScene*)h;
  TemporalAntiAliasingOptions t;
  t.enabled = taa != 0;
  s->view->setTemporalAntiAliasingOptions(t);
  if (taa) s->view->setAntiAliasing(View::AntiAliasing::NONE);   // TAA replaces FXAA
  else s->view->setAntiAliasing(View::AntiAliasing::FXAA);
  DepthOfFieldOptions d;
  d.enabled = dofFocus > 0 && dofBlur > 0;
  d.cocScale = dofBlur;
  s->view->setDepthOfFieldOptions(d);
  if (dofFocus > 0) s->camera->setFocusDistance(dofFocus);
  ScreenSpaceReflectionsOptions r;
  r.enabled = ssr != 0;
  s->view->setScreenSpaceReflectionsOptions(r);
  VignetteOptions v;
  v.enabled = vignette > 0;
  v.midPoint = 0.5f;
  v.roundness = 0.5f;
  v.feather = 0.5f;
  v.color = {0, 0, 0, 1};
  v.midPoint = 1.0f - 0.6f * (vignette > 1 ? 1 : vignette);
  s->view->setVignetteOptions(v);
  if (s->grading) { s->view->setColorGrading(nullptr); s->engine->destroy(s->grading); s->grading = nullptr; }
  delete s->toneMapper;
  switch (toneMap) {
    case 1: s->toneMapper = new FilmicToneMapper(); break;
    case 2: s->toneMapper = new AgxToneMapper(); break;
    case 3: s->toneMapper = new PBRNeutralToneMapper(); break;
    case 4: s->toneMapper = new LinearToneMapper(); break;
    default: s->toneMapper = new ACESToneMapper(); break;
  }
  s->grading = ColorGrading::Builder().toneMapper(s->toneMapper).exposure(exposure)
      .contrast(contrast > 0 ? contrast : 1.0f).saturation(saturation >= 0 ? saturation : 1.0f).build(*s->engine);
  s->view->setColorGrading(s->grading);
  View::FogOptions fog = s->view->getFogOptions();
  fog.height = fogHeight;
  fog.heightFalloff = fogFalloff > 0 ? fogFalloff : 1.0f;
  s->view->setFogOptions(fog);
}

static void freeRt(YfScene* s, YfScene::Rt& r) {
  if (r.view) s->engine->destroy(r.view);
  if (r.target) s->engine->destroy(r.target);
  if (r.color) s->engine->destroy(r.color);
  if (r.depth) s->engine->destroy(r.depth);
  if (r.camera) s->engine->destroyCameraComponent(r.camEntity);
  r = YfScene::Rt();
}

// A camera that draws the scene into a w x h texture called `key` (usable as any map), from eye
// to target with a vertical fov. Made, moved, or remade at a new size; w <= 0 removes it.
YF_API int yf_rt(void* h, const char* key, int w, int ht, float ex, float ey, float ez, float tx, float ty, float tz,
                 float fov) {
  YfScene* s = (YfScene*)h;
  if (!key) return 0;
  auto it = s->rts.find(key);
  if (w <= 0 || ht <= 0) {
    if (it != s->rts.end()) { s->textures.erase(key); freeRt(s, it->second); s->rts.erase(it); }
    return 1;
  }
  YfScene::Rt& r = s->rts[key];
  if (r.w != w || r.h != ht) {
    int bit = r.bit;
    if (!bit) {                           // a free layer bit, 1..7 (bit 0: everything else)
      for (int b = 1; b < 8 && !bit; b++) {
        bool used = false;
        for (auto& kv : s->rts) if (kv.second.bit == b) used = true;
        if (!used) bit = b;
      }
      if (!bit) { s->error = "at most 7 cameras draw into textures"; s->rts.erase(key); return 0; }
    }
    freeRt(s, r);
    r.bit = bit;
    r.w = w; r.h = ht;
    r.color = Texture::Builder().width(w).height(ht).levels(1).format(Texture::InternalFormat::RGBA8)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE).sampler(Texture::Sampler::SAMPLER_2D)
        .build(*s->engine);
    r.depth = Texture::Builder().width(w).height(ht).levels(1).format(Texture::InternalFormat::DEPTH24)
        .usage(Texture::Usage::DEPTH_ATTACHMENT).sampler(Texture::Sampler::SAMPLER_2D).build(*s->engine);
    r.target = RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR, r.color)
        .texture(RenderTarget::AttachmentPoint::DEPTH, r.depth).build(*s->engine);
    r.camEntity = utils::EntityManager::get().create();
    r.camera = s->engine->createCamera(r.camEntity);
    r.view = s->engine->createView();
    r.view->setScene(s->scene);
    r.view->setCamera(r.camera);
    r.view->setRenderTarget(r.target);
    r.view->setViewport({0, 0, (uint32_t)w, (uint32_t)ht});
    r.view->setPostProcessingEnabled(false);      // a plain picture: the main view grades it
    r.view->setVisibleLayers(0xFF, (uint8_t)(0xFF & ~(1 << r.bit)));
    s->textures[key] = r.color;
  }
  r.camera->setProjection(fov > 0 ? fov : 45.0, double(w) / double(ht), 0.1, 1000.0, Camera::Fov::VERTICAL);
  r.camera->lookAt({ex, ey, ez}, {tx, ty, tz}, {0, 1, 0});
  return 1;
}

// Mesh `id` shows camera texture `key`: that camera does not draw it (a mirror never films itself).
YF_API void yf_obj_shows(void* h, int id, const char* key) {
  YfScene* s = (YfScene*)h;
  if (id < 0 || id >= (int)s->objs.size() || s->objs[id].kind != 1) return;
  uint8_t layer = 1;
  auto it = key ? s->rts.find(key) : s->rts.end();
  if (it != s->rts.end()) layer = (uint8_t)(1 << it->second.bit);
  auto& rm = s->engine->getRenderableManager();
  for (auto p : s->objs[id].parts) rm.setLayerMask(rm.getInstance(p), 0xFF, layer);
}

// The camera, without re-framing: eye, target, vertical field of view, near and far planes.
YF_API void yf_camera_ex(void* h, float ex, float ey, float ez, float tx, float ty, float tz,
                         float fov, float nearZ, float farZ) {
  YfScene* s = (YfScene*)h;
  if (fov > 0) s->fov = fov;
  s->camera->setProjection(s->fov, double(s->w) / double(s->h), nearZ > 0 ? nearZ : 0.1,
                           farZ > 0 ? farZ : 1000.0, Camera::Fov::VERTICAL);
  s->camera->lookAt({ex, ey, ez}, {tx, ty, tz}, {0, 1, 0});
}

YF_API const char* yf_error(void* h) { return ((YfScene*)h)->error.c_str(); }

YF_API void yf_destroy(void* h) {
  YfScene* s = (YfScene*)h;
  for (int i = 0; i < (int)s->objs.size(); i++) yf_obj_remove(h, i);
  for (Material* m : s->lit) if (m) s->engine->destroy(m);
  if (s->flat) s->engine->destroy(s->flat);
  for (auto& kv : s->rts) { s->textures.erase(kv.first); freeRt(s, kv.second); }
  for (auto& kv : s->shaders) s->engine->destroy(kv.second);
  for (auto& kv : s->textures) s->engine->destroy(kv.second);
  if (s->white) s->engine->destroy(s->white);
  if (s->sky) s->engine->destroy(s->sky);
  if (s->grading) s->engine->destroy(s->grading);
  delete s->toneMapper;
  if (s->asset) { s->scene->removeEntities(s->asset->getEntities(), s->asset->getEntityCount()); s->loader->destroyAsset(s->asset); }
  delete s->resources;
  delete s->stb;
  AssetLoader::destroy(&s->loader);
  delete s->names;
  s->materials->destroyMaterials();
  delete s->materials;
  s->engine->destroy(s->indirect);
  s->engine->destroy(s->sun);
  s->engine->destroyCameraComponent(s->cameraEntity);
  s->engine->destroy(s->view);
  s->engine->destroy(s->scene);
  s->engine->destroy(s->renderer);
  s->engine->destroy(s->swap);
  Engine::destroy(&s->engine);
  delete s;
}
