// skia_shim.cpp — a small C API over Skia for the Yantra native engine.
//
// Only what the renderer needs: a raster canvas over caller-owned pixels, filled
// and stroked rounded rects, clipping, and paragraph text (SkParagraph, which
// shapes with HarfBuzz and handles bidi and fallback — Hindi works). Paragraphs
// are cached by (text, size, weight, max width) because layout is the expensive
// part and the same labels are drawn every frame.

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkMaskFilter.h"
#include "include/core/SkBlurTypes.h"
#include "include/effects/SkGradientShader.h"
#include <map>
#include "include/utils/SkParsePath.h"
#include <cmath>
#include "include/core/SkRRect.h"
#include "include/core/SkSurface.h"
#ifdef __EMSCRIPTEN__
#include "include/ports/SkFontMgr_empty.h"
#include "modules/skparagraph/include/TypefaceFontProvider.h"
#include <dirent.h>
#else
#include "include/ports/SkTypeface_win.h"
#endif
#include "modules/skparagraph/include/FontCollection.h"
#include "modules/skparagraph/include/Paragraph.h"
#include "modules/skparagraph/include/ParagraphBuilder.h"
#include "modules/skparagraph/include/ParagraphStyle.h"
#include "modules/skparagraph/include/TextStyle.h"
#include "modules/skunicode/include/SkUnicode_icu.h"

#include <list>
#include <memory>
#include <string>
#include <unordered_map>

using namespace skia::textlayout;

namespace {

struct Fonts {
  sk_sp<SkFontMgr> mgr;
  sk_sp<FontCollection> collection;
  sk_sp<SkUnicode> unicode;
  // LRU paragraph cache
  std::list<std::string> order;
  std::unordered_map<std::string, std::pair<std::unique_ptr<Paragraph>, std::list<std::string>::iterator>> cache;
  size_t capacity = 512;
};

Fonts* g_fonts = nullptr;

Fonts* fonts() {
  if (!g_fonts) {
    g_fonts = new Fonts();
    g_fonts->collection = sk_make_sp<FontCollection>();
#ifdef __EMSCRIPTEN__
    // The browser has no font manager Skia can use: the page ships open fonts in /fonts
    // (sans.ttf, mono.ttf, and any others), registered under the names the engine asks for.
    g_fonts->mgr = SkFontMgr_New_Custom_Empty();
    auto provider = sk_make_sp<TypefaceFontProvider>();
    if (DIR* d = opendir("/fonts")) {
      while (dirent* e = readdir(d)) {
        std::string name = e->d_name;
        if (name.size() < 5) continue;
        sk_sp<SkTypeface> tf = g_fonts->mgr->makeFromFile(("/fonts/" + name).c_str());
        if (!tf) continue;
        provider->registerTypeface(tf);
        bool mono = name.rfind("mono", 0) == 0;
        for (const char* alias : mono ? std::initializer_list<const char*>{"Cascadia Mono", "Consolas"}
                                      : std::initializer_list<const char*>{"Segoe UI", "Nirmala UI"})
          provider->registerTypeface(tf, SkString(alias));
      }
      closedir(d);
    }
    g_fonts->collection->setDefaultFontManager(provider);
#else
    g_fonts->mgr = SkFontMgr_New_DirectWrite();
    g_fonts->collection->setDefaultFontManager(g_fonts->mgr);
#endif
    g_fonts->collection->enableFontFallback();
    g_fonts->unicode = SkUnicodes::ICU::Make();
  }
  return g_fonts;
}

struct TextOpts {
  const char* family = nullptr;   // nullptr = the default stack
  int italic = 0;
  float lineHeight = 0;           // multiple of the font size; 0 = the font's own
  int maxLines = 0;               // 0 = unlimited; otherwise ellipsised
};

std::string key(const char* s, int len, float size, int weight, float maxW, unsigned argb, int align,
                const TextOpts& o) {
  std::string k(s, (size_t)len);
  k.push_back('\x1f');
  k += std::to_string(size) + "|" + std::to_string(weight) + "|" + std::to_string(maxW) + "|" +
       std::to_string(argb) + "|" + std::to_string(align) + "|" + (o.family ? o.family : "") + "|" +
       std::to_string(o.italic) + "|" + std::to_string(o.lineHeight) + "|" + std::to_string(o.maxLines);
  return k;
}

Paragraph* paragraph(const char* s, int len, float size, int weight, float maxW, unsigned argb, int align,
                     const TextOpts& o = TextOpts()) {
  Fonts* f = fonts();
  std::string k = key(s, len, size, weight, maxW, argb, align, o);
  auto it = f->cache.find(k);
  if (it != f->cache.end()) {
    f->order.splice(f->order.begin(), f->order, it->second.second);
    return it->second.first.get();
  }
  ParagraphStyle ps;
  ps.setTextAlign(align == 1 ? TextAlign::kCenter : align == 2 ? TextAlign::kRight : TextAlign::kLeft);
  bool rtl = o.family && o.family[0] == '\x1d';     // right-to-left (P9): nimskia TextStyle.rtl
  if (rtl) {
    ps.setTextDirection(TextDirection::kRtl);
    // align 0 is "start": the right edge, when the paragraph has a width to align in
    ps.setTextAlign(align == 1 ? TextAlign::kCenter : align == 2 ? TextAlign::kLeft : maxW > 0 ? TextAlign::kRight : TextAlign::kLeft);
  }
  TextStyle ts;
  ts.setFontSize(size);
  ts.setColor(SkColor(argb));
  // rich text: the family string may carry styled runs after a \x1e (see nimskia TextStyle.spans):
  // "start,end,flags,argb,size;…" in bytes; flags 1 bold, 2 italic, 4 underline, 8 strike, 16 mono
  std::string fam = o.family ? o.family + (rtl ? 1 : 0) : "";
  std::string inl;                               // inline objects (Q3): "w,h;w,h" after a \x1c
  size_t isep = fam.find('\x1c');
  if (isep != std::string::npos) { inl = fam.substr(isep + 1); fam = fam.substr(0, isep); }
  std::string spans;
  size_t sep = fam.find('\x1e');
  if (sep != std::string::npos) { spans = fam.substr(sep + 1); fam = fam.substr(0, sep); }
  if (!fam.empty())
    ts.setFontFamilies({SkString(fam.c_str()), SkString("Segoe UI"), SkString("Nirmala UI"), SkString("Segoe UI Emoji")});
  else
    ts.setFontFamilies({SkString("Segoe UI"), SkString("Nirmala UI"), SkString("Segoe UI Emoji")});
  ts.setFontStyle(SkFontStyle(weight, SkFontStyle::kNormal_Width,
                              o.italic ? SkFontStyle::kItalic_Slant : SkFontStyle::kUpright_Slant));
  if (o.lineHeight > 0) { ts.setHeight(o.lineHeight); ts.setHeightOverride(true); }
  ps.setTextStyle(ts);
  if (o.maxLines > 0) { ps.setMaxLines((size_t)o.maxLines); ps.setEllipsis(u"\u2026"); }
  auto builder = ParagraphBuilder::make(ps, f->collection, f->unicode);
  builder->pushStyle(ts);
  // each U+FFFC in the text becomes the next inline object's box (an image or emoji the
  // engine draws there): a placeholder is one UTF-16 unit, like the character, so byte
  // offsets map the same
  std::vector<std::pair<float, float>> boxes;
  for (size_t q = 0; q < inl.size();) {
    size_t e = inl.find(';', q);
    if (e == std::string::npos) e = inl.size();
    float bw = 0, bh = 0;
    if (sscanf(inl.substr(q, e - q).c_str(), "%f,%f", &bw, &bh) == 2) boxes.push_back({bw, bh});
    q = e + 1;
  }
  size_t nextBox = 0;
  auto addRun = [&](const char* t, size_t n) {
    size_t from = 0;
    for (size_t i = 0; boxes.size() > nextBox && i + 2 < n + 0 && i + 3 <= n; ++i) {
      if ((unsigned char)t[i] == 0xEF && (unsigned char)t[i + 1] == 0xBF && (unsigned char)t[i + 2] == 0xBC) {
        if (i > from) builder->addText(t + from, i - from);
        auto bx = boxes[nextBox++];
        builder->addPlaceholder(PlaceholderStyle(bx.first, bx.second, PlaceholderAlignment::kMiddle,
                                                 TextBaseline::kAlphabetic, 0));
        from = i + 3;
        i += 2;
        if (nextBox >= boxes.size()) break;
      }
    }
    if (n > from) builder->addText(t + from, n - from);
  };
  if (spans.empty()) {
    addRun(s, (size_t)len);
  } else {
    size_t at = 0, pos = 0;
    while (pos < spans.size()) {
      size_t end = spans.find(';', pos);
      if (end == std::string::npos) end = spans.size();
      long a = 0, b = 0, flags = 0, size2 = 0; unsigned long col = 0;
      if (sscanf(spans.substr(pos, end - pos).c_str(), "%ld,%ld,%ld,%lu,%ld", &a, &b, &flags, &col, &size2) >= 3 &&
          a >= (long)at && b > a && b <= len) {
        if ((size_t)a > at) addRun(s + at, (size_t)a - at);
        TextStyle rs = ts;
        if (flags & 1) rs.setFontStyle(SkFontStyle(700, SkFontStyle::kNormal_Width, rs.getFontStyle().slant()));
        if (flags & 2) rs.setFontStyle(SkFontStyle(rs.getFontStyle().weight(), SkFontStyle::kNormal_Width, SkFontStyle::kItalic_Slant));
        int deco = 0;
        if (flags & 4) deco |= TextDecoration::kUnderline;
        if (flags & 8) deco |= TextDecoration::kLineThrough;
        if (deco) { rs.setDecoration((TextDecoration)deco); rs.setDecorationColor(col ? SkColor(col) : SkColor(argb)); }
        if (flags & 16) rs.setFontFamilies({SkString("Cascadia Mono"), SkString("Consolas"), SkString("Segoe UI")});
        if (col) rs.setColor(SkColor(col));
        if (size2 > 0) rs.setFontSize((float)size2);
        builder->pushStyle(rs);
        addRun(s + a, (size_t)(b - a));
        builder->pop();
        at = (size_t)b;
      }
      pos = end + 1;
    }
    if (at < (size_t)len) addRun(s + at, (size_t)len - at);
  }
  auto p = builder->Build();
  p->layout(maxW > 0 ? maxW : 1e6f);
  Paragraph* raw = p.get();
  f->order.push_front(k);
  f->cache.emplace(k, std::make_pair(std::move(p), f->order.begin()));
  if (f->cache.size() > f->capacity) {
    f->cache.erase(f->order.back());
    f->order.pop_back();
  }
  return raw;
}

}  // namespace

extern "C" {

void* yk_canvas_new(void* pixels, int w, int h, int rowBytes) {
  SkImageInfo info = SkImageInfo::MakeN32Premul(w, h);
  auto c = SkCanvas::MakeRasterDirect(info, pixels, (size_t)rowBytes);
  return c.release();
}

void yk_canvas_free(void* c) { delete static_cast<SkCanvas*>(c); }

void yk_clear(void* c, unsigned argb) { static_cast<SkCanvas*>(c)->clear(SkColor(argb)); }

void yk_save(void* c) { static_cast<SkCanvas*>(c)->save(); }
void yk_restore(void* c) { static_cast<SkCanvas*>(c)->restore(); }
void yk_translate(void* c, float x, float y) { static_cast<SkCanvas*>(c)->translate(x, y); }
void yk_scale(void* c, float s) { static_cast<SkCanvas*>(c)->scale(s, s); }
void yk_rotate(void* c, float deg) { static_cast<SkCanvas*>(c)->rotate(deg); }
void yk_clip_rect(void* c, float x, float y, float w, float h) {
  static_cast<SkCanvas*>(c)->clipRect(SkRect::MakeXYWH(x, y, w, h), true);
}

void yk_rrect(void* c, float x, float y, float w, float h, float r, unsigned argb) {
  SkPaint p;
  p.setAntiAlias(true);
  p.setColor(SkColor(argb));
  static_cast<SkCanvas*>(c)->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r), p);
}

void yk_rrect_stroke(void* c, float x, float y, float w, float h, float r, float width, unsigned argb) {
  SkPaint p;
  p.setAntiAlias(true);
  p.setStyle(SkPaint::kStroke_Style);
  p.setStrokeWidth(width);
  p.setColor(SkColor(argb));
  float i = width / 2;
  static_cast<SkCanvas*>(c)->drawRRect(
      SkRRect::MakeRectXY(SkRect::MakeXYWH(x + i, y + i, w - width, h - width), r, r), p);
}

// Strokes an open polyline (xy pairs) with round caps and joins: ticks, chevrons.
void yk_polyline(void* c, const float* xy, int n, float width, unsigned argb) {
  if (n < 2) return;
  SkPathBuilder b;
  b.moveTo(xy[0], xy[1]);
  for (int i = 1; i < n; i++) b.lineTo(xy[2 * i], xy[2 * i + 1]);
  SkPaint p;
  p.setAntiAlias(true);
  p.setStyle(SkPaint::kStroke_Style);
  p.setStrokeWidth(width);
  p.setStrokeCap(SkPaint::kRound_Cap);
  p.setStrokeJoin(SkPaint::kRound_Join);
  p.setColor(SkColor(argb));
  static_cast<SkCanvas*>(c)->drawPath(b.detach(), p);
}

// Measures a paragraph laid out at maxW (<= 0 means unbounded). Returns the
// width the text actually needs; *outH receives its height.
float yk_text_measure(const char* s, int len, float size, int weight, float maxW, float* outH) {
  if (len <= 0) { if (outH) *outH = size * 1.2f; return 0; }
  Paragraph* p = paragraph(s, len, size, weight, maxW, 0xff000000u, 0);
  if (outH) *outH = p->getHeight();
  float w = p->getMaxIntrinsicWidth();
  if (maxW > 0 && w > maxW) w = maxW;
  return w;
}

void yk_text_draw(void* c, const char* s, int len, float size, int weight, float maxW,
                  float x, float y, unsigned argb, int align) {
  if (len <= 0) return;
  Paragraph* p = paragraph(s, len, size, weight, maxW, argb, align);
  p->paint(static_cast<SkCanvas*>(c), x, y);
}

// X offset of the caret after `bytes` bytes of text (for text inputs).
float yk_text_caret_x(const char* s, int len, int bytes, float size, int weight) {
  if (bytes <= 0 || len <= 0) return 0;
  if (bytes > len) bytes = len;
  float h = 0;
  return yk_text_measure(s, bytes, size, weight, 0, &h);
}

}  // extern "C"

extern "C" {

// Text with every option. Returns width; *outH gets the height.
float yk_text_measure2(const char* s, int len, float size, int weight, float maxW, float* outH,
                       const char* family, int italic, float lineHeight, int maxLines) {
  TextOpts o; o.family = family; o.italic = italic; o.lineHeight = lineHeight; o.maxLines = maxLines;
  if (len <= 0) { if (outH) *outH = size * (lineHeight > 0 ? lineHeight : 1.2f); return 0; }
  Paragraph* p = paragraph(s, len, size, weight, maxW, 0xff000000u, 0, o);
  if (outH) *outH = p->getHeight();
  float w = p->getMaxIntrinsicWidth();
  if (maxW > 0 && w > maxW) w = maxW;
  return w;
}

void yk_text_draw2(void* c, const char* s, int len, float size, int weight, float maxW,
                   float x, float y, unsigned argb, int align,
                   const char* family, int italic, float lineHeight, int maxLines) {
  if (len <= 0) return;
  TextOpts o; o.family = family; o.italic = italic; o.lineHeight = lineHeight; o.maxLines = maxLines;
  Paragraph* p = paragraph(s, len, size, weight, maxW, argb, align, o);
  p->paint(static_cast<SkCanvas*>(c), x, y);
}

// --- text editing geometry (T1). Positions are UTF-8 byte offsets on our side and
// UTF-16 code units inside SkParagraph; these two convert.
static int u8to16(const char* s, int len, int bytes) {
  int u = 0;
  for (int i = 0; i < len && i < bytes;) {
    unsigned char c = (unsigned char)s[i];
    int n = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
    u += n == 4 ? 2 : 1;
    i += n;
  }
  return u;
}
static int u16to8(const char* s, int len, int u16) {
  int u = 0, i = 0;
  while (i < len && u < u16) {
    unsigned char c = (unsigned char)s[i];
    int n = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
    u += n == 4 ? 2 : 1;
    i += n;
  }
  return i > len ? len : i;
}
static Paragraph* editPara(const char* s, int len, float size, int weight, float maxW,
                           const char* family, int italic, float lineHeight) {
  TextOpts o; o.family = family; o.italic = italic; o.lineHeight = lineHeight;
  return paragraph(s, len, size, weight, maxW, 0xff000000u, 0, o);
}

// Where the caret goes after `bytes` bytes: top-left x, y and its height. Handles
// wrapped and hard-broken ("\n") lines and right-to-left runs.
void yk_text_caret(const char* s, int len, int bytes, float size, int weight, float maxW,
                   const char* family, int italic, float lineHeight, float* ox, float* oy, float* oh) {
  float lh = size * (lineHeight > 0 ? lineHeight : 1.2f);
  *ox = 0; *oy = 0; *oh = lh;
  if (len <= 0) return;
  if (bytes > len) bytes = len;
  if (bytes < 0) bytes = 0;
  Paragraph* p = editPara(s, len, size, weight, maxW, family, italic, lineHeight);
  int i = u8to16(s, len, bytes), n = u8to16(s, len, len);
  bool afterBreak = bytes > 0 && s[bytes - 1] == '\n';
  if (i < n && (i == 0 || afterBreak)) {                 // left edge of the next character
    auto r = p->getRectsForRange(i, i + 1, RectHeightStyle::kMax, RectWidthStyle::kTight);
    if (!r.empty()) {
      bool rtl = r[0].direction == TextDirection::kRtl;
      *ox = rtl ? r[0].rect.fRight : r[0].rect.fLeft; *oy = r[0].rect.fTop; *oh = r[0].rect.height();
      return;
    }
  }
  if (afterBreak) {                                      // an empty last line
    *ox = 0; *oy = p->getHeight() - lh; *oh = lh;
    return;
  }
  if (i > 0) {                                           // right edge of the previous character
    auto r = p->getRectsForRange(i - 1, i, RectHeightStyle::kMax, RectWidthStyle::kTight);
    if (!r.empty()) {
      bool rtl = r.back().direction == TextDirection::kRtl;
      *ox = rtl ? r.back().rect.fLeft : r.back().rect.fRight; *oy = r.back().rect.fTop; *oh = r.back().rect.height();
    }
  }
}

// The byte offset nearest to point (x, y) in the laid-out text.
int yk_text_hit(const char* s, int len, float x, float y, float size, int weight, float maxW,
                const char* family, int italic, float lineHeight) {
  if (len <= 0) return 0;
  Paragraph* p = editPara(s, len, size, weight, maxW, family, italic, lineHeight);
  auto pos = p->getGlyphPositionAtCoordinate(x, y);
  return u16to8(s, len, pos.position);
}

// Rectangles covering bytes [from, to): up to maxRects of them as x, y, w, h.
int yk_text_rects(const char* s, int len, int from, int to, float size, int weight, float maxW,
                  const char* family, int italic, float lineHeight, float* out, int maxRects) {
  if (len <= 0 || to <= from) return 0;
  Paragraph* p = editPara(s, len, size, weight, maxW, family, italic, lineHeight);
  auto r = p->getRectsForRange(u8to16(s, len, from), u8to16(s, len, to), RectHeightStyle::kMax,
                               RectWidthStyle::kTight);
  int n = 0;
  for (auto& b : r) {
    if (n >= maxRects) break;
    out[4 * n] = b.rect.fLeft; out[4 * n + 1] = b.rect.fTop;
    out[4 * n + 2] = b.rect.width(); out[4 * n + 3] = b.rect.height();
    n++;
  }
  return n;
}

// Where the inline objects (U+FFFC boxes, Q3) landed: up to max of them as x, y, w, h.
int yk_text_placeholders(const char* s, int len, float size, int weight, float maxW, int align,
                         const char* family, int italic, float lineHeight, int maxLines, float* out, int max) {
  if (len <= 0) return 0;
  TextOpts o; o.family = family; o.italic = italic; o.lineHeight = lineHeight; o.maxLines = maxLines;
  Paragraph* p = paragraph(s, len, size, weight, maxW, 0xff000000u, align, o);
  auto r = p->getRectsForPlaceholders();
  int n = 0;
  for (auto& b : r) {
    if (n >= max) break;
    out[4 * n] = b.rect.fLeft; out[4 * n + 1] = b.rect.fTop;
    out[4 * n + 2] = b.rect.width(); out[4 * n + 3] = b.rect.height();
    n++;
  }
  return n;
}

// A rounded rect filled with a linear gradient; angle in degrees, 90 = top to bottom.
void yk_rrect_gradient(void* c, float x, float y, float w, float h, float r,
                       unsigned from, unsigned to, float angleDeg) {
  float a = angleDeg * 3.14159265f / 180.f;
  float cx = x + w / 2, cy = y + h / 2;
  float dx = std::cos(a) * w / 2, dy = std::sin(a) * h / 2;
  SkPoint pts[2] = {{cx - dx, cy - dy}, {cx + dx, cy + dy}};
  SkColor cols[2] = {SkColor(from), SkColor(to)};
  SkPaint p;
  p.setAntiAlias(true);
  p.setShader(SkGradientShader::MakeLinear(pts, cols, nullptr, 2, SkTileMode::kClamp));
  static_cast<SkCanvas*>(c)->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r), p);
}

// A soft shadow under a rounded rect: the shape offset by (dx, dy), blurred by `blur`.
void yk_shadow(void* c, float x, float y, float w, float h, float r,
               float dx, float dy, float blur, unsigned argb) {
  SkPaint p;
  p.setAntiAlias(true);
  p.setColor(SkColor(argb));
  if (blur > 0) p.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, blur / 2));
  static_cast<SkCanvas*>(c)->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x + dx, y + dy, w, h), r, r), p);
}

// Group opacity: everything drawn until the matching restore is faded together.
void yk_save_alpha(void* c, float alpha) {
  int a = (int)std::lround(alpha * 255.f);
  if (a < 0) a = 0;
  if (a > 255) a = 255;
  static_cast<SkCanvas*>(c)->saveLayerAlpha(nullptr, (U8CPU)a);
}

// SVG path data drawn at (x, y), scaled by `scale`; stroked when strokeWidth > 0, else filled.
// Parsed paths are cached by their text.
void yk_svg_path(void* c, const char* d, float x, float y, float scale, float strokeWidth, unsigned argb) {
  static std::unordered_map<std::string, SkPath> cache;
  std::string key(d ? d : "");
  auto it = cache.find(key);
  if (it == cache.end()) {
    auto parsed = SkParsePath::FromSVGString(key.c_str());
    if (!parsed) return;
    it = cache.emplace(key, *parsed).first;
  }
  SkCanvas* cv = static_cast<SkCanvas*>(c);
  SkPaint p;
  p.setAntiAlias(true);
  p.setColor(SkColor(argb));
  if (strokeWidth > 0) {
    p.setStyle(SkPaint::kStroke_Style);
    p.setStrokeWidth(strokeWidth);
    p.setStrokeCap(SkPaint::kRound_Cap);
    p.setStrokeJoin(SkPaint::kRound_Join);
  }
  cv->save();
  cv->translate(x, y);
  cv->scale(scale, scale);
  cv->drawPath(it->second, p);
  cv->restore();
}

}  // extern "C"

// --- U8: pixels from elsewhere (decoded video frames) -------------------------------
#include "include/core/SkImage.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSamplingOptions.h"

extern "C" {

// Draws a BGRA pixel buffer (pw x ph, opaque) into the box x, y, w, h: fit 0 contain,
// 1 cover, 2 fill (stretch); corners rounded by r. The pixels are not copied.
void yk_draw_pixels(void* c, const void* pixels, int pw, int ph, float x, float y, float w, float h,
                    float r, int fit) {
  if (!pixels || pw <= 0 || ph <= 0 || w <= 0 || h <= 0) return;
  SkPixmap pm(SkImageInfo::Make(pw, ph, kBGRA_8888_SkColorType, kPremul_SkAlphaType), pixels, (size_t)pw * 4);  // premultiplied: 3D frames are transparent around the model
  sk_sp<SkImage> img = SkImages::RasterFromPixmap(pm, nullptr, nullptr);
  if (!img) return;
  SkCanvas* cv = static_cast<SkCanvas*>(c);
  SkRect box = SkRect::MakeXYWH(x, y, w, h);
  SkRect dst = box;
  if (fit != 2) {
    float s = fit == 1 ? std::max(w / pw, h / ph) : std::min(w / pw, h / ph);
    float dw = pw * s, dh = ph * s;
    dst = SkRect::MakeXYWH(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh);
  }
  cv->save();
  cv->clipRRect(SkRRect::MakeRectXY(box, r, r), true);
  cv->drawImageRect(img, dst, SkSamplingOptions(SkFilterMode::kLinear, SkMipmapMode::kNone));
  cv->restore();
}

}  // extern "C"

// --- FX1: effects as props (blur, glass, blend, colour, SkSL shaders) -----------------
#include "include/effects/SkImageFilters.h"
#include "include/effects/SkRuntimeEffect.h"
#include "include/effects/SkColorMatrix.h"
#include "include/core/SkColorFilter.h"
#include "include/core/SkBlendMode.h"
#include "include/core/SkM44.h"

namespace {
struct ShaderEntry { sk_sp<SkRuntimeEffect> effect; std::string error; };
std::unordered_map<std::string, ShaderEntry> g_shaders;

ShaderEntry& shaderFor(const char* src) {
  std::string k(src);
  auto it = g_shaders.find(k);
  if (it != g_shaders.end()) return it->second;
  auto result = SkRuntimeEffect::MakeForShader(SkString(src));
  ShaderEntry e{result.effect, result.effect ? "" : std::string(result.errorText.c_str())};
  return g_shaders.emplace(k, e).first->second;
}
}  // namespace

extern "C" {

// Starts a layer for a node's effects; everything drawn until the matching restores goes
// through it. blur: blur of the node itself (px); backdrop: blur of what is behind it
// inside x,y,w,h rounded by r (frosted glass); blend: an SkBlendMode (-1 = normal);
// saturate/brightness/contrast: 1 = unchanged; alpha: the node's opacity. Returns how
// many restores it needs (1 or 2).
int yk_save_fx(void* c, float x, float y, float w, float h, float r, float blur, float backdrop, int blend,
               float saturate, float brightness, float contrast, float alpha) {
  SkCanvas* cv = static_cast<SkCanvas*>(c);
  SkPaint p;
  p.setAlphaf(alpha < 0 ? 0 : alpha > 1 ? 1 : alpha);
  if (blur > 0) p.setImageFilter(SkImageFilters::Blur(blur / 2, blur / 2, SkTileMode::kDecal, nullptr));
  if (saturate != 1 || brightness != 1 || contrast != 1) {
    SkColorMatrix m;
    m.setSaturation(saturate);
    SkColorMatrix bc;                    // brightness and contrast around mid grey
    float s = brightness * contrast, t = 0.5f * (1 - contrast);
    bc.setScale(s, s, s, 1);
    bc.postTranslate(t, t, t, 0);
    m.postConcat(bc);
    p.setColorFilter(SkColorFilters::Matrix(m));
  }
  if (blend >= 0 && blend <= (int)SkBlendMode::kLastMode) p.setBlendMode((SkBlendMode)blend);
  int saves = 1;
  if (backdrop > 0) {
    cv->save();
    cv->clipRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r), true);
    saves = 2;
    auto bf = SkImageFilters::Blur(backdrop / 2, backdrop / 2, SkTileMode::kClamp, nullptr);
    cv->saveLayer(SkCanvas::SaveLayerRec(nullptr, &p, bf.get(), 0));
  } else {
    cv->saveLayer(nullptr, &p);
  }
  return saves;
}

// Fills a rounded rect with an SkSL shader. Its coordinates are local to the box; it may
// declare `uniform float2 size;` and `uniform float time;` (seconds). 1 on success, else 0
// with the compile error in err.
int yk_shader_rrect(void* c, const char* src, float x, float y, float w, float h, float r, float time,
                    char* err, int cap) {
  ShaderEntry& e = shaderFor(src);
  if (!e.effect) {
    snprintf(err, (size_t)cap, "%s", e.error.c_str());
    return 0;
  }
  SkRuntimeShaderBuilder b(e.effect);
  if (b.uniform("size").fVar) b.uniform("size") = SkV2{w, h};
  if (b.uniform("time").fVar) b.uniform("time") = time;
  SkMatrix local = SkMatrix::Translate(x, y);
  auto shader = b.makeShader(&local);
  if (!shader) { snprintf(err, (size_t)cap, "the shader could not be made"); return 0; }
  SkPaint p;
  p.setAntiAlias(true);
  p.setShader(shader);
  static_cast<SkCanvas*>(c)->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r), p);
  return 1;
}

// Whether a shader reads `time` (then it animates); -1 if it does not compile.
int yk_shader_uses_time(const char* src) {
  ShaderEntry& e = shaderFor(src);
  if (!e.effect) return -1;
  return e.effect->findUniform("time") ? 1 : 0;
}

}  // extern "C"

#ifndef __EMSCRIPTEN__   // PDF and GPU are desktop-only for now
// --- D1: PDF documents (vector, real text) -----------------------------------------
#include "include/docs/SkPDFDocument.h"
#include "include/docs/SkPDFJpegHelpers.h"
#include "include/core/SkStream.h"

namespace {
struct YkPdf {
  std::unique_ptr<SkFILEWStream> stream;
  sk_sp<SkDocument> doc;
};
}  // namespace

extern "C" {

// Opens `path` for a PDF; nullptr if the file cannot be written.
void* yk_pdf_open(const char* path, const char* title, const char* author) {
  auto s = std::make_unique<SkFILEWStream>(path);
  if (!s->isValid()) return nullptr;
  SkPDF::Metadata m = SkPDF::JPEG::MetadataWithCallbacks();   // photos go in as JPEG
  m.fTitle = title;
  m.fAuthor = author;
  m.fCreator = "Yantra";
  m.fProducer = "Yantra (Skia PDF)";
  auto doc = SkPDF::MakeDocument(s.get(), m);
  if (!doc) return nullptr;
  return new YkPdf{std::move(s), doc};
}

// Starts a page of w x h points; returns the canvas to draw it with (owned by the document).
void* yk_pdf_page(void* h, float w, float hgt) {
  return static_cast<YkPdf*>(h)->doc->beginPage(w, hgt);
}

void yk_pdf_end_page(void* h) { static_cast<YkPdf*>(h)->doc->endPage(); }

// Finishes the file and frees the document.
void yk_pdf_close(void* h) {
  auto* y = static_cast<YkPdf*>(h);
  y->doc->close();
  y->stream->flush();
  delete y;
}

}  // extern "C"

// --- U5: the GPU (Ganesh on OpenGL) ---------------------------------------------------
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/gl/GrGLDirectContext.h"
#include "include/gpu/ganesh/gl/GrGLInterface.h"
#include "include/gpu/ganesh/gl/GrGLBackendSurface.h"
#include "include/gpu/ganesh/gl/GrGLTypes.h"

extern "C" {

// A GPU context on the OpenGL context current on this thread; nullptr if none.
void* yk_gpu_new() {
  auto iface = GrGLMakeNativeInterface();
  if (!iface) return nullptr;
  return GrDirectContexts::MakeGL(iface).release();
}

void yk_gpu_free(void* ctx) { if (ctx) static_cast<GrDirectContext*>(ctx)->unref(); }

// A surface on the window's default framebuffer (w x h device pixels).
void* yk_gpu_window_surface(void* ctx, int w, int h) {
  GrGLFramebufferInfo fb;
  fb.fFBOID = 0;
  fb.fFormat = 0x8058;                    // GL_RGBA8
  auto rt = GrBackendRenderTargets::MakeGL(w, h, 0, 8, fb);
  return SkSurfaces::WrapBackendRenderTarget(static_cast<GrDirectContext*>(ctx), rt, kBottomLeft_GrSurfaceOrigin,
                                             kRGBA_8888_SkColorType, nullptr, nullptr).release();
}

// An off-screen GPU surface (for tests, thumbnails and GPU film frames).
void* yk_gpu_offscreen(void* ctx, int w, int h) {
  return SkSurfaces::RenderTarget(static_cast<GrDirectContext*>(ctx), skgpu::Budgeted::kNo,
                                  SkImageInfo::MakeN32Premul(w, h)).release();
}

void* yk_surface_canvas(void* s) { return static_cast<SkSurface*>(s)->getCanvas(); }
void yk_surface_free(void* s) { if (s) static_cast<SkSurface*>(s)->unref(); }

// Sends the frame's GPU work; `sync` waits until it is done (for timing and read-back).
void yk_gpu_flush(void* ctx, int sync) {
  static_cast<GrDirectContext*>(ctx)->flushAndSubmit(sync ? GrSyncCpu::kYes : GrSyncCpu::kNo);
}

// Copies a surface's pixels (BGRA premultiplied, w x h) into `pixels`. 1 on success.
int yk_surface_read(void* s, void* pixels, int w, int h) {
  return static_cast<SkSurface*>(s)->readPixels(SkImageInfo::MakeN32Premul(w, h), pixels, (size_t)w * 4, 0, 0) ? 1 : 0;
}

}  // extern "C"

#else
extern "C" {
void* yk_pdf_open(const char*, const char*, const char*) { return nullptr; }
void* yk_pdf_page(void*, float, float) { return nullptr; }
void yk_pdf_end_page(void*) {}
void yk_pdf_close(void*) {}
void* yk_gpu_new() { return nullptr; }
void yk_gpu_free(void*) {}
void* yk_gpu_window_surface(void*, int, int) { return nullptr; }
void* yk_gpu_offscreen(void*, int, int) { return nullptr; }
void* yk_surface_canvas(void*) { return nullptr; }
void yk_surface_free(void*) {}
void yk_gpu_flush(void*, int) {}
int yk_surface_read(void*, void*, int, int) { return 0; }
}
#endif

// --- Image support (N1) --------------------------------------------------------

#include "include/codec/SkCodec.h"
#include "include/codec/SkPngDecoder.h"
#include "include/codec/SkJpegDecoder.h"
#include "include/codec/SkBmpDecoder.h"
#ifndef __EMSCRIPTEN__   // WebP is not in the web build of Skia yet
#include "include/codec/SkWebpDecoder.h"
#else                    // GIF needs wuffs: only the web build has it (MSYS2's Skia: skia_use_wuffs=false)
#include "include/codec/SkGifDecoder.h"
#endif
#include "include/core/SkBitmap.h"
#include "include/core/SkStream.h"
#include "include/encode/SkPngEncoder.h"
#include "include/core/SkData.h"
#include <atomic>
#include <chrono>
#include <deque>
#include <mutex>
#include <unordered_set>
#include <vector>
#ifndef __EMSCRIPTEN__
#include <condition_variable>
#include <thread>
#endif

// --- the image pipeline (P2) ----------------------------------------------------------
// Images decode off the UI thread (two workers), at the smallest power-of-two reduction
// that still covers the size they are drawn at, into an LRU cache with a byte cap.
// Animated WebP (and GIF on the web) keep every frame at that size. A draw that finds
// nothing ready queues a decode and returns "loading"; the engine polls `yk_img_generation`.
namespace {

struct ImgInfo { int w = 0, h = 0, frames = 0; bool ok = false; };
struct ImgEntry {
  std::string key;
  std::vector<sk_sp<SkImage>> frames;
  std::vector<int> durMs;                 // per frame; empty for a still
  int totalMs = 0;
  long long bytes = 0;
};
struct Job { std::string path; int level; };

std::mutex g_imgMu;
std::unordered_map<std::string, ImgInfo> g_imgInfo;          // path -> header facts
std::list<ImgEntry> g_lru;                                     // front = most recently drawn
std::unordered_map<std::string, std::list<ImgEntry>::iterator> g_lruAt;
std::unordered_set<std::string> g_failed;                      // keys that did not decode
std::unordered_set<std::string> g_queued;                      // keys waiting or decoding
std::deque<Job> g_jobs;                                        // newest first
long long g_bytes = 0;
long long g_limit = 128ll << 20;
int g_busy = 0;
std::atomic<int> g_generation{0};
const size_t kMaxJobs = 64;                                    // older requests are dropped (scrolled away)
const int kMaxLevel = 5;                                       // at most 1/32
#ifndef __EMSCRIPTEN__
std::condition_variable g_imgCv, g_idleCv;
bool g_workersUp = false;
#endif

std::string keyOf(const std::string& path, int level) { return path + "\n" + std::to_string(level); }

std::unique_ptr<SkCodec> makeCodec(sk_sp<SkData> data) {
  if (!data || data->size() == 0) return nullptr;
  SkCodec::Result res;
  const void* ptr = data->data();
  size_t sz = data->size();
  if (SkPngDecoder::IsPng(ptr, sz)) return SkPngDecoder::Decode(data, &res);
  if (SkJpegDecoder::IsJpeg(ptr, sz)) return SkJpegDecoder::Decode(data, &res);
  if (SkBmpDecoder::IsBmp(ptr, sz)) return SkBmpDecoder::Decode(data, &res);
#ifndef __EMSCRIPTEN__
  if (SkWebpDecoder::IsWebp(ptr, sz)) return SkWebpDecoder::Decode(data, &res);
#else
  if (SkGifDecoder::IsGif(ptr, sz)) return SkGifDecoder::Decode(data, &res);
#endif
  return nullptr;
}

ImgInfo infoOf(const std::string& path) {
  // header only: no pixels are decoded (callers hold g_imgMu)
  auto it = g_imgInfo.find(path);
  if (it != g_imgInfo.end()) return it->second;
  ImgInfo inf;
  auto codec = makeCodec(SkData::MakeFromFileName(path.c_str()));
  if (codec) {
    inf.w = codec->dimensions().width();
    inf.h = codec->dimensions().height();
    inf.frames = std::max(1, codec->getFrameCount());
    inf.ok = inf.w > 0 && inf.h > 0;
  }
  g_imgInfo[path] = inf;
  return inf;
}

sk_sp<SkImage> scaledImage(const SkBitmap& src, int tw, int th) {
  if (src.width() == tw && src.height() == th) {
    SkBitmap copy = src;
    copy.setImmutable();
    return SkImages::RasterFromBitmap(copy);
  }
  SkBitmap out;
  if (!out.tryAllocPixels(src.info().makeWH(tw, th))) return nullptr;
  if (!src.pixmap().scalePixels(out.pixmap(), SkSamplingOptions(SkCubicResampler::Mitchell()))) return nullptr;
  out.setImmutable();
  return SkImages::RasterFromBitmap(out);
}

bool decodeInto(const std::string& path, int level, ImgEntry& e) {
  // Runs on a worker (no lock held): only local objects are touched.
  auto codec = makeCodec(SkData::MakeFromFileName(path.c_str()));
  if (!codec) return false;
  SkISize full = codec->dimensions();
  if (full.isEmpty()) return false;
  const int div = 1 << level;
  const int tw = std::max(1, (full.width() + div - 1) / div);
  const int th = std::max(1, (full.height() + div - 1) / div);
  const int count = std::max(1, codec->getFrameCount());
  if (count == 1 || (long long)tw * th * 4 * count > g_limit / 4) {
    // a still (or an animation too big to keep): JPEG scales while decoding (DCT), others after
    SkISize dec = codec->getScaledDimensions(1.0f / div);
    if (dec.width() < tw || dec.height() < th) dec = full;
    SkImageInfo info = SkImageInfo::MakeN32Premul(dec.width(), dec.height());
    SkBitmap bm;
    if (!bm.tryAllocPixels(info)) return false;
    auto r = codec->getPixels(info, bm.getPixels(), bm.rowBytes());
    if (r != SkCodec::kSuccess && r != SkCodec::kIncompleteInput && r != SkCodec::kErrorInInput) return false;
    auto img = scaledImage(bm, tw, th);
    if (!img) return false;
    e.frames.push_back(img);
  } else {
    // every frame at full size first (frames build on earlier ones), kept at the drawn size
    auto infos = codec->getFrameInfo();
    SkImageInfo info = SkImageInfo::MakeN32Premul(full.width(), full.height());
    SkBitmap prev;                                   // only the last full frame is kept
    int prevIndex = -1;
    for (int i = 0; i < count && i < (int)infos.size(); ++i) {
      SkBitmap cur;
      if (!cur.tryAllocPixels(info)) return false;
      SkCodec::Options opts;
      opts.fFrameIndex = i;
      int req = infos[i].fRequiredFrame;
      if (req != SkCodec::kNoFrame && req == prevIndex) {
        prev.readPixels(cur.pixmap());
        opts.fPriorFrame = req;
      } else {
        // no earlier frame needed; or one older than the last, which the codec decodes itself
        cur.eraseColor(SK_ColorTRANSPARENT);
      }
      auto r = codec->getPixels(info, cur.getPixels(), cur.rowBytes(), &opts);
      if (r != SkCodec::kSuccess && r != SkCodec::kIncompleteInput && r != SkCodec::kErrorInInput) break;
      auto img = scaledImage(cur, tw, th);
      if (!img) return false;
      e.frames.push_back(img);
      int d = infos[i].fDuration;
      e.durMs.push_back(d <= 10 ? 100 : d);          // what browsers do with 0 and 10 ms frames
      e.totalMs += e.durMs.back();
      prev = cur;
      prevIndex = i;
    }
    if (e.frames.empty()) return false;
    if (e.frames.size() == 1) { e.durMs.clear(); e.totalMs = 0; }
  }
  for (auto& f : e.frames) e.bytes += (long long)f->width() * f->height() * 4;
  return true;
}

void evictLocked() {
  while (g_bytes > g_limit && g_lru.size() > 1) {
    auto& last = g_lru.back();
    g_bytes -= last.bytes;
    g_lruAt.erase(last.key);
    g_lru.pop_back();
  }
}

void storeLocked(ImgEntry&& e) {
  auto it = g_lruAt.find(e.key);
  if (it != g_lruAt.end()) {
    g_bytes -= it->second->bytes;
    g_lru.erase(it->second);
  }
  g_bytes += e.bytes;
  g_lru.push_front(std::move(e));
  g_lruAt[g_lru.front().key] = g_lru.begin();
  evictLocked();
}

void runJob(const Job& j) {
  ImgEntry e;
  e.key = keyOf(j.path, j.level);
  bool ok = decodeInto(j.path, j.level, e);
  std::lock_guard<std::mutex> lk(g_imgMu);
  g_queued.erase(e.key);
  if (ok) storeLocked(std::move(e)); else g_failed.insert(keyOf(j.path, j.level));
  g_generation.fetch_add(1);
}

#ifndef __EMSCRIPTEN__
void worker() {
  for (;;) {
    Job j;
    {
      std::unique_lock<std::mutex> lk(g_imgMu);
      g_imgCv.wait(lk, [] { return !g_jobs.empty(); });
      j = g_jobs.front();
      g_jobs.pop_front();
      ++g_busy;
    }
    runJob(j);
    {
      std::lock_guard<std::mutex> lk(g_imgMu);
      --g_busy;
    }
    g_idleCv.notify_all();
  }
}
#endif

void requestLocked(const std::string& path, int level) {
  std::string k = keyOf(path, level);
  if (g_queued.count(k) || g_failed.count(k)) return;
  g_queued.insert(k);
  g_jobs.push_front({path, level});
  while (g_jobs.size() > kMaxJobs) {           // the oldest asks were for images long scrolled away
    g_queued.erase(keyOf(g_jobs.back().path, g_jobs.back().level));
    g_jobs.pop_back();
  }
#ifndef __EMSCRIPTEN__
  if (!g_workersUp) {
    g_workersUp = true;
    for (int i = 0; i < 2; ++i) std::thread(worker).detach();
  }
  g_imgCv.notify_one();
#endif
}

int levelFor(const ImgInfo& inf, float needW, float needH) {
  int k = 0;
  while (k < kMaxLevel && (inf.w >> (k + 1)) >= needW && (inf.h >> (k + 1)) >= needH) ++k;
  return k;
}

// The cached image for `path` to draw at `level`: that level, else a finer one, else a
// coarser one (a stand-in while the right one decodes). `exact` says which it is.
ImgEntry* findLocked(const std::string& path, int level, bool& exact) {
  exact = false;
  for (int k = level; k >= 0; --k) {
    auto it = g_lruAt.find(keyOf(path, k));
    if (it != g_lruAt.end()) { exact = true; return &*it->second; }
  }
  for (int k = level + 1; k <= kMaxLevel; ++k) {
    auto it = g_lruAt.find(keyOf(path, k));
    if (it != g_lruAt.end()) return &*it->second;
  }
  return nullptr;
}

void touchLocked(ImgEntry* e) {
  auto it = g_lruAt.find(e->key);
  if (it != g_lruAt.end() && it->second != g_lru.begin()) g_lru.splice(g_lru.begin(), g_lru, it->second);
}

void drawFit(SkCanvas* cv, const sk_sp<SkImage>& img, float iw, float ih, float x, float y, float w, float h,
             float r, int fit, float alpha) {
  // iw, ih: the image's own size (a reduced decode still maps onto the whole of it)
  const float sx = img->width() / iw, sy = img->height() / ih;
  SkRect srcRect = SkRect::MakeWH(img->width(), img->height());
  SkRect dstRect = SkRect::MakeXYWH(x, y, w, h);
  if (fit == 1) {                 // cover: fill dst, centre crop src
    float scale = std::max(w / iw, h / ih);
    float cropW = w / scale, cropH = h / scale;
    srcRect = SkRect::MakeXYWH((iw - cropW) / 2 * sx, (ih - cropH) / 2 * sy, cropW * sx, cropH * sy);
  } else if (fit == 0) {          // contain: letterbox inside dst
    float scale = std::min(w / iw, h / ih);
    float fitW = iw * scale, fitH = ih * scale;
    dstRect = SkRect::MakeXYWH(x + (w - fitW) / 2, y + (h - fitH) / 2, fitW, fitH);
  }
  SkPaint paint;
  paint.setAntiAlias(true);
  if (alpha < 1) paint.setAlphaf(std::max(0.0f, alpha));
  SkSamplingOptions sampling(SkFilterMode::kLinear);
  if (r > 0) {
    cv->save();
    cv->clipRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r), true);
  }
  cv->drawImageRect(img.get(), srcRect, dstRect, sampling, &paint, SkCanvas::kFast_SrcRectConstraint);
  if (r > 0) cv->restore();
}

}  // namespace

extern "C" {

bool yk_write_png(const char* path, int w, int h, unsigned argb) {
  if (!path || w <= 0 || h <= 0) return false;
  SkBitmap bm;
  bm.allocN32Pixels(w, h);
  bm.eraseColor(SkColor(argb));
  SkFILEWStream stream(path);
  return SkPngEncoder::Encode(&stream, bm.pixmap(), {});
}

bool yk_image_info(const char* path, int* outW, int* outH) {
  if (!path || !path[0]) return false;
  std::lock_guard<std::mutex> lk(g_imgMu);
  ImgInfo inf = infoOf(path);
  if (!inf.ok) return false;
  if (outW) *outW = inf.w;
  if (outH) *outH = inf.h;
  return true;
}

int yk_image_frames(const char* path) {
  if (!path || !path[0]) return 0;
  std::lock_guard<std::mutex> lk(g_imgMu);
  ImgInfo inf = infoOf(path);
  return inf.ok ? inf.frames : 0;
}

// Draws `path` into (x, y, w, h). level < 0: pick it from the size it lands on the device;
// sync: decode now if nothing is cached (exports, tests). Returns 1 drawn, 2 drawn and
// animated (draw again for the next frame), 3 drawn a stand-in while the right size decodes,
// 0 loading (nothing drawn), -1 not an image.
int yk_img_draw(void* c, const char* path, float x, float y, float w, float h, float r, int fit,
                float alpha, double tMs, int level, int sync) {
  if (!c || !path || !path[0] || w <= 0 || h <= 0) return -1;
  SkCanvas* cv = static_cast<SkCanvas*>(c);
  std::string p(path);
  ImgInfo inf;
  sk_sp<SkImage> img;
  bool exact = false, animated = false;
  {
    std::lock_guard<std::mutex> lk(g_imgMu);
    inf = infoOf(p);
    if (!inf.ok) return -1;
    if (level < 0) {
      float s = cv->getTotalMatrix().getMaxScale();
      if (!(s > 0)) s = 1;
      float k = fit == 1 ? std::max(w / inf.w, h / inf.h) : fit == 0 ? std::min(w / inf.w, h / inf.h)
                         : std::max(w / inf.w, h / inf.h);
      level = levelFor(inf, inf.w * k * s, inf.h * k * s);
    }
    level = std::min(std::max(level, 0), kMaxLevel);
    ImgEntry* e = findLocked(p, level, exact);
    if (!exact && !sync) requestLocked(p, level);
    if (!exact && sync) e = nullptr;
    if (e) {
      touchLocked(e);
      size_t i = 0;
      if (e->totalMs > 0 && e->frames.size() > 1) {
        animated = true;
        long long t = (long long)std::max(0.0, tMs) % e->totalMs;
        while (i + 1 < e->frames.size() && t >= e->durMs[i]) { t -= e->durMs[i]; ++i; }
      }
      img = e->frames[i];
    } else if (g_failed.count(keyOf(p, level))) {
      return -1;
    }
  }
  if (!img && sync) {                          // on this thread, now
    ImgEntry e;
    e.key = keyOf(p, level);
    if (!decodeInto(p, level, e)) {
      std::lock_guard<std::mutex> lk(g_imgMu);
      g_failed.insert(e.key);
      return -1;
    }
    img = e.frames[0];
    animated = e.frames.size() > 1;
    exact = true;
    std::lock_guard<std::mutex> lk(g_imgMu);
    storeLocked(std::move(e));
  }
  if (!img) return 0;
  drawFit(cv, img, (float)inf.w, (float)inf.h, x, y, w, h, r, fit, alpha);
  return animated ? 2 : exact ? 1 : 3;
}

void yk_draw_image(void* c, const char* path, float x, float y, float w, float h, float r, int fit) {
  // the older call: full size, decoded now
  yk_img_draw(c, path, x, y, w, h, r, fit, 1.0f, 0, 0, 1);
}

int yk_img_generation() { return g_generation.load(); }

void yk_img_cache_limit(long long bytes) {
  std::lock_guard<std::mutex> lk(g_imgMu);
  g_limit = std::max(1ll << 20, bytes);
  evictLocked();
}

void yk_img_stats(int* count, long long* bytes, int* pending) {
  std::lock_guard<std::mutex> lk(g_imgMu);
  if (count) *count = (int)g_lru.size();
  if (bytes) *bytes = g_bytes;
  if (pending) *pending = (int)g_jobs.size() + g_busy;
}

// Blocks until every queued decode is done (tests, exports); false on timeout.
bool yk_img_wait(int timeoutMs) {
#ifdef __EMSCRIPTEN__
  // no threads: run what is queued here
  for (;;) {
    Job j;
    {
      std::lock_guard<std::mutex> lk(g_imgMu);
      if (g_jobs.empty()) return true;
      j = g_jobs.front();
      g_jobs.pop_front();
    }
    runJob(j);
  }
#else
  std::unique_lock<std::mutex> lk(g_imgMu);
  return g_idleCv.wait_for(lk, std::chrono::milliseconds(timeoutMs), [] { return g_jobs.empty() && g_busy == 0; });
#endif
}

// Forget everything about `path` (the file changed).
void yk_img_forget(const char* path) {
  if (!path) return;
  std::lock_guard<std::mutex> lk(g_imgMu);
  std::string p(path);
  g_imgInfo.erase(p);
  for (int k = 0; k <= kMaxLevel; ++k) {
    std::string key = keyOf(p, k);
    g_failed.erase(key);
    auto it = g_lruAt.find(key);
    if (it != g_lruAt.end()) {
      g_bytes -= it->second->bytes;
      g_lru.erase(it->second);
      g_lruAt.erase(it);
    }
  }
}

}  // extern "C"

// --- canvas node (P7): a batched draw-command list from the app, replayed with Skia ------
// Commands are separated by ';', their numbers by spaces or commas; colours are ARGB
// integers (decimal or 0x hex). Coordinates are the node's own logical px.
//   M x y | L x y | Q x1 y1 x y | C x1 y1 x2 y2 x y | A cx cy r start sweep | Z   build a path
//   F argb                     fill it            S argb width         stroke it (then a new path)
//   R x y w h radius argb      fill a rect        B x y w h radius argb width   stroke one
//   E cx cy rx ry argb         fill an ellipse    G x1 y1 x2 y2 argb width      a line
//   T x y size argb weight text                   text (the rest of the command, ';' as "\;")
//   I x y w h fit path                            an image from the app's folder (path resolved by the engine)
//   P / p save / restore       K x y w h clip     t dx dy | s sx sy | o degrees   transform
//   O alpha                    opacity of what follows, until restore
extern "C" void yk_text_draw(void* c, const char* s, int len, float size, int weight, float maxW, float x, float y,
                             unsigned argb, int align);
extern "C" int yk_img_draw(void* c, const char* path, float x, float y, float w, float h, float r, int fit,
                           float alpha, double tMs, int level, int sync);

namespace {
struct CmdReader {
  const char* p; const char* end;
  void skipSep() { while (p < end && (*p == ' ' || *p == ',' || *p == '\t' || *p == '\n')) ++p; }
  float num() {
    skipSep();
    char* q = nullptr;
    float v = strtof(p, &q);
    if (q == p) return 0;
    p = q;
    return v;
  }
  unsigned color() {
    skipSep();
    char* q = nullptr;
    unsigned long long v = strtoull(p, &q, 0);
    if (q == p) return 0xFF000000u;
    p = q;
    return (unsigned)v;
  }
  std::string rest() {                         // up to the next unescaped ';'
    skipSep();
    std::string s;
    while (p < end && *p != ';') {
      if (*p == '\\' && p + 1 < end && p[1] == ';') { s += ';'; p += 2; continue; }
      s += *p++;
    }
    return s;
  }
  void toNext() { while (p < end && *p != ';') ++p; if (p < end) ++p; }
};
}  // namespace

// --- raster layers and bulk pixels (CV2) -------------------------------------------------
// A layer is a bitmap an app keeps and draws into over time (a painting's strokes, a
// simulation's frames); a canvas shows it with 'Y'. Ids are the app's, offset by the engine's
// layer base so apps never see each other's. 'X' draws raw RGBA pixels from a y_buf buffer.
static std::map<int, sk_sp<SkSurface>> g_layers;
static int g_layerBase = 0;
typedef const void* (*yk_buf_fn)(int id, int* len);
static yk_buf_fn g_bufFn = nullptr;
extern "C" void yk_canvas_env(int layerBase, void* bufFn) { g_layerBase = layerBase; g_bufFn = (yk_buf_fn)bufFn; }

static int runCmds(SkCanvas* cv, const char* cmds, int len, float ox, float oy, float w, float h,
                   const char* assetDir, double tMs);

extern "C" int yk_canvas_run(void* c, const char* cmds, int len, float ox, float oy, float w, float h,
                             const char* assetDir, double tMs) {
  // Replays `cmds` with the node's top-left at (ox, oy), clipped to w x h. Returns 1 if an
  // image was still loading or animated (draw again later).
  if (!c || !cmds) return 0;
  return runCmds(static_cast<SkCanvas*>(c), cmds, len, ox, oy, w, h, assetDir, tMs);
}

extern "C" int yk_layer_new(int id, int w, int h) {
  if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return 0;
  sk_sp<SkSurface> s = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(w, h));
  if (!s) return 0;
  s->getCanvas()->clear(SK_ColorTRANSPARENT);
  g_layers[id] = s;
  return 1;
}
extern "C" void yk_layer_free(int id) { g_layers.erase(id); }
extern "C" int yk_layer_draw(int id, const char* cmds, int len, const char* assetDir) {
  auto it = g_layers.find(id);
  if (it == g_layers.end() || !cmds) return 0;
  SkSurface* s = it->second.get();
  runCmds(s->getCanvas(), cmds, len, 0, 0, (float)s->width(), (float)s->height(), assetDir, 0);
  return 1;
}
// In place: 0 blur (amount = radius px), 1 brightness (-1..1), 2 contrast (0 grey .. 1 same .. 2),
// 3 saturation (0 grey .. 1 same .. 2), 4 invert, 5 greyscale, 6 sepia, 7 opacity (0..1).
extern "C" int yk_layer_filter(int id, int kind, float amount) {
  auto it = g_layers.find(id);
  if (it == g_layers.end()) return 0;
  SkSurface* s = it->second.get();
  sk_sp<SkImage> img = s->makeImageSnapshot();
  SkPaint p;
  SkColorMatrix m;
  switch (kind) {
    case 0: p.setImageFilter(SkImageFilters::Blur(amount * 0.5f, amount * 0.5f, SkTileMode::kDecal, nullptr)); break;
    case 1: m.setScale(1, 1, 1, 1); m.postTranslate(amount, amount, amount, 0); break;
    case 2: { float t = 0.5f * (1 - amount);
              float a[20] = {amount, 0, 0, 0, t, 0, amount, 0, 0, t, 0, 0, amount, 0, t, 0, 0, 0, 1, 0};
              m.setRowMajor(a); break; }
    case 3: m.setSaturation(amount); break;
    case 4: { float a[20] = {-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0}; m.setRowMajor(a); break; }
    case 5: m.setSaturation(0); break;
    case 6: { float a[20] = {0.393f, 0.769f, 0.189f, 0, 0, 0.349f, 0.686f, 0.168f, 0, 0,
                             0.272f, 0.534f, 0.131f, 0, 0, 0, 0, 0, 1, 0}; m.setRowMajor(a); break; }
    case 7: p.setAlphaf(amount < 0 ? 0 : (amount > 1 ? 1 : amount)); break;
    default: return 0;
  }
  if (kind >= 1 && kind <= 6) p.setColorFilter(SkColorFilters::Matrix(m));
  SkCanvas* cv = s->getCanvas();
  cv->clear(SK_ColorTRANSPARENT);
  cv->drawImage(img, 0, 0, SkSamplingOptions(), &p);
  return 1;
}
// RGBA, not premultiplied (what an app computes with), top row first.
extern "C" int yk_layer_read(int id, int x, int y, int w, int h, void* out) {
  auto it = g_layers.find(id);
  if (it == g_layers.end() || !out) return 0;
  SkImageInfo info = SkImageInfo::Make(w, h, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
  return it->second->readPixels(info, out, (size_t)w * 4, x, y) ? 1 : 0;
}
extern "C" int yk_layer_write(int id, int x, int y, int w, int h, const void* in) {
  auto it = g_layers.find(id);
  if (it == g_layers.end() || !in) return 0;
  SkImageInfo info = SkImageInfo::Make(w, h, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
  SkPixmap pm(info, in, (size_t)w * 4);
  it->second->writePixels(pm, x, y);
  return 1;
}
extern "C" int yk_layer_size(int id, int* w, int* h) {
  auto it = g_layers.find(id);
  if (it == g_layers.end()) return 0;
  *w = it->second->width(); *h = it->second->height();
  return 1;
}

static int runCmds(SkCanvas* cv, const char* cmds, int len, float ox, float oy, float w, float h,
                   const char* assetDir, double tMs) {
  void* c = cv;
  int again = 0;
  SkBlendMode blend = SkBlendMode::kSrcOver;
  std::vector<SkBlendMode> blends;
  cv->save();
  cv->clipRect(SkRect::MakeXYWH(ox, oy, w, h));
  cv->translate(ox, oy);
  int depth = 0;
  float alpha = 1;
  std::vector<float> alphas;
  SkPathBuilder path;
  CmdReader r{cmds, cmds + len};
  std::string dir = assetDir ? assetDir : "";
  while (r.p < r.end) {
    r.skipSep();
    if (r.p >= r.end) break;
    char op = *r.p++;
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setBlendMode(blend);
    auto colour = [&](unsigned argb) { paint.setColor(SkColor(argb)); if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha); };
    switch (op) {
      case ';': continue;
      case 'M': { float x = r.num(), y = r.num(); path.moveTo(x, y); break; }
      case 'L': { float x = r.num(), y = r.num(); path.lineTo(x, y); break; }
      case 'Q': { float a = r.num(), b = r.num(), x = r.num(), y = r.num(); path.quadTo(a, b, x, y); break; }
      case 'C': { float a = r.num(), b = r.num(), d = r.num(), e = r.num(), x = r.num(), y = r.num(); path.cubicTo(a, b, d, e, x, y); break; }
      case 'A': { float cx = r.num(), cy = r.num(), rad = r.num(), st = r.num(), sw = r.num();
                  path.arcTo(SkRect::MakeLTRB(cx - rad, cy - rad, cx + rad, cy + rad), st, sw, false); break; }
      case 'Z': path.close(); break;
      case 'F': { colour(r.color()); cv->drawPath(path.detach(), paint); break; }
      case 'S': { colour(r.color()); paint.setStyle(SkPaint::kStroke_Style); paint.setStrokeWidth(r.num());
                  paint.setStrokeJoin(SkPaint::kRound_Join); paint.setStrokeCap(SkPaint::kRound_Cap);
                  cv->drawPath(path.detach(), paint); break; }
      case 'R': { float x = r.num(), y = r.num(), ww = r.num(), hh = r.num(), rad = r.num(); colour(r.color());
                  cv->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, ww, hh), rad, rad), paint); break; }
      case 'B': { float x = r.num(), y = r.num(), ww = r.num(), hh = r.num(), rad = r.num(); colour(r.color());
                  paint.setStyle(SkPaint::kStroke_Style); paint.setStrokeWidth(r.num());
                  cv->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, ww, hh), rad, rad), paint); break; }
      case 'E': { float cx = r.num(), cy = r.num(), rx = r.num(), ry = r.num(); colour(r.color());
                  cv->drawOval(SkRect::MakeLTRB(cx - rx, cy - ry, cx + rx, cy + ry), paint); break; }
      case 'G': { float x1 = r.num(), y1 = r.num(), x2 = r.num(), y2 = r.num(); colour(r.color());
                  paint.setStrokeWidth(r.num()); paint.setStrokeCap(SkPaint::kRound_Cap);
                  cv->drawLine(x1, y1, x2, y2, paint); break; }
      case 'T': { float x = r.num(), y = r.num(), size = r.num(); unsigned col = r.color(); int wt = (int)r.num();
                  std::string s = r.rest();
                  if (alpha < 1) col = (col & 0x00FFFFFFu) | ((unsigned)((col >> 24) * alpha) << 24);
                  yk_text_draw(c, s.c_str(), (int)s.size(), size, wt > 0 ? wt : 400, 0, x, y, col, 0); break; }
      // DECISION_QUEUE D6 — text with an explicit family. Purely additive: 'T' above is
      // untouched, so every module already in the tree emits identical bytes.
      //   N <x> <y> <size> <argb> <weight> <family>;<text>;
      // family and text are two separate ';'-terminated fields with NO space between
      // them, because rest() stops at the ';'.
      case 'N': { float x = r.num(), y = r.num(), size = r.num(); unsigned col = r.color(); int wt = (int)r.num();
                  std::string fam = r.rest();      // family, up to the first ';'
                  r.toNext();                      // CONSUME that ';' — rest() stops AT it
                  std::string s = r.rest();        // text, up to the second ';'
                  if (alpha < 1) col = (col & 0x00FFFFFFu) | ((unsigned)((col >> 24) * alpha) << 24);
                  // yk_text_draw2 (:318) already accepted a family; it was simply
                  // unreachable from runCmds. nullptr is explicitly handled at :132
                  // (o.family ? ... : "") and yields the exact existing fallback at :141.
                  yk_text_draw2(c, s.c_str(), (int)s.size(), size, wt > 0 ? wt : 400, 0, x, y, col, 0,
                                fam.empty() ? nullptr : fam.c_str(), 0, 0, 0);
                  break; }
      case 'I': { float x = r.num(), y = r.num(), ww = r.num(), hh = r.num(); int fit = (int)r.num();
                  std::string rel = r.rest();
                  // the app's own folder only: no drive, no root, no backslash, no ".."
                  if (!dir.empty() && !rel.empty() && rel[0] != '/' && rel.find(':') == std::string::npos &&
                      rel.find('\\') == std::string::npos && rel.find("..") == std::string::npos) {
                    int st = yk_img_draw(c, (dir + "/" + rel).c_str(), x, y, ww, hh, 0, fit, alpha, tMs, -1, 0);
                    if (st == 0 || st == 2 || st == 3) again = 1;
                  }
                  break; }
      case 'P': cv->save(); alphas.push_back(alpha); blends.push_back(blend); ++depth; break;
      case 'p': if (depth > 0) { cv->restore(); alpha = alphas.back(); alphas.pop_back(); blend = blends.back(); blends.pop_back(); --depth; } break;
      case 'b': { int m = (int)r.num(); if (m >= 0 && m <= (int)SkBlendMode::kLastMode) blend = (SkBlendMode)m; break; }
      case 'Y': { int id = (int)r.num(); float x = r.num(), y = r.num(), ww = r.num(), hh = r.num();
                  auto it = g_layers.find(g_layerBase + id);
                  if (it != g_layers.end()) {
                    SkPaint lp; lp.setBlendMode(blend); lp.setAlphaf(alpha);
                    sk_sp<SkImage> img = it->second->makeImageSnapshot();
                    if (ww <= 0) ww = (float)img->width();
                    if (hh <= 0) hh = (float)img->height();
                    cv->drawImageRect(img, SkRect::MakeXYWH(x, y, ww, hh), SkSamplingOptions(SkFilterMode::kLinear), &lp);
                  }
                  break; }
      case 'X': { int id = (int)r.num(); int pw = (int)r.num(), ph = (int)r.num();
                  float x = r.num(), y = r.num(), ww = r.num(), hh = r.num();
                  int n = 0;
                  const void* px = g_bufFn ? g_bufFn(id, &n) : nullptr;
                  if (px && pw > 0 && ph > 0 && n >= pw * ph * 4) {
                    SkPixmap pm(SkImageInfo::Make(pw, ph, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType), px, (size_t)pw * 4);
                    sk_sp<SkImage> img = SkImages::RasterFromPixmapCopy(pm);
                    SkPaint lp; lp.setBlendMode(blend); lp.setAlphaf(alpha);
                    if (img) cv->drawImageRect(img, SkRect::MakeXYWH(x, y, ww > 0 ? ww : pw, hh > 0 ? hh : ph),
                                               SkSamplingOptions(), &lp);   // nearest: pixels stay crisp
                  }
                  break; }
      case 'V': { float x = r.num(), y = r.num(), scale = r.num(), sw = r.num();
                  unsigned col = r.color();          // before rest(): it runs to the ';'
                  std::string d = r.rest();
                  if (auto parsed = SkParsePath::FromSVGString(d.c_str())) {
                    paint.setColor(SkColor(col));
                    if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha);
                    cv->save();
                    cv->translate(x, y);
                    if (scale != 1) cv->scale(scale, scale);
                    if (sw > 0) {
                      paint.setStyle(SkPaint::kStroke_Style);
                      paint.setStrokeWidth(sw);
                      paint.setStrokeJoin(SkPaint::kRound_Join);
                      paint.setStrokeCap(SkPaint::kRound_Cap);
                    }
                    cv->drawPath(*parsed, paint);
                    cv->restore();
                  }
                  break; }
      case 'K': { float x = r.num(), y = r.num(), ww = r.num(), hh = r.num(); cv->clipRect(SkRect::MakeXYWH(x, y, ww, hh), true); break; }
      case 't': { float x = r.num(), y = r.num(); cv->translate(x, y); break; }
      case 's': { float x = r.num(), y = r.num(); cv->scale(x, y == 0 ? x : y); break; }
      case 'o': cv->rotate(r.num()); break;
      case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;
      default: break;                            // unknown: skipped, so newer apps still draw on older engines
    }
    r.toNext();
  }
  while (depth-- > 0) cv->restore();
  cv->restore();
  return again;
}

// --- saving pixels (Q2: a camera photo) --------------------------------------------------
#include "include/encode/SkJpegEncoder.h"
extern "C" bool yk_save_pixels(const char* path, const void* bgra, int w, int h) {
  // BGRA (premultiplied, opaque for camera frames) -> .png, or .jpg/.jpeg at quality 90
  if (!path || !bgra || w <= 0 || h <= 0) return false;
  SkPixmap pm(SkImageInfo::Make(w, h, kBGRA_8888_SkColorType, kPremul_SkAlphaType), bgra, (size_t)w * 4);
  SkFILEWStream out(path);
  if (!out.isValid()) return false;
  std::string p(path);
  auto ends = [&](const char* x) { size_t n = strlen(x); return p.size() >= n && p.compare(p.size() - n, n, x) == 0; };
  if (ends(".jpg") || ends(".jpeg")) { SkJpegEncoder::Options o; o.fQuality = 90; return SkJpegEncoder::Encode(&out, pm, o); }
  return SkPngEncoder::Encode(&out, pm, {});
}
