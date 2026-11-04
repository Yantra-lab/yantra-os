// nimqt — C++ shim compiled directly by Nim ({.compile: "shim.cpp".}).
//
// Purpose:
//  * UTF-safe QString <-> Nim string conversions without dangling temporaries.
//  * const char* accessors re-exposed as QString BY VALUE.
//  * QGuiApplication bootstrap (owns argv storage).
//  * QQmlComponent async incubation state machine (opaque handles).
//  * QJSValue::call/construct with C arrays of values.
//  * Error-list, root-object-list and grab-result conversions.
//
// Every function is extern "C" and exception-safe: no C++ exception may cross
// into Nim (no unwinding personality on the Nim side).

#include <cstring>
#include <QString>
#include <QByteArray>
#include <QVariant>
#include <QUrl>
#include <QStringList>
#include <QMetaObject>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QMetaEnum>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlProperty>
#include <QJSValue>
#include <QQmlApplicationEngine>
#include <QQmlIncubator>
#include <QJSEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQuickView>
#include <cstdio>
#include <QQuickItemGrabResult>
#include <QList>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlExpression>

#define NIMQT_BEGIN extern "C" {
#define NIMQT_END }

NIMQT_BEGIN

// --- QString <-> UTF-8 ------------------------------------------------------

int nimqt_qstr_utf8_size(const QString s) {
  return int(s.toUtf8().size());
}

void nimqt_qstr_utf8_copy(const QString s, char* buf) {
  const QByteArray ba = s.toUtf8();
  if (buf && ba.size() > 0)
    memcpy(buf, ba.constData(), size_t(ba.size()));
}

// --- QMetaObject / QMetaMethod / QMetaProperty / QMetaEnum ------------------
// All return QString by value (copied immediately by the Nim side).

QString nimqt_mo_class_name(const QMetaObject* m) {
  return m ? QString::fromUtf8(m->className()) : QString();
}

QString nimqt_mm_signature(const QMetaMethod mm) {
  return QString::fromUtf8(mm.methodSignature());
}

QString nimqt_mm_name(const QMetaMethod mm) {
  return QString::fromUtf8(mm.name());
}

QString nimqt_mp_name(const QMetaProperty mp) {
  return QString::fromUtf8(mp.name());
}

QString nimqt_mp_type_name(const QMetaProperty mp) {
  return QString::fromUtf8(mp.typeName());
}

QString nimqt_me_name(const QMetaEnum me) {
  return QString::fromUtf8(me.name());
}

// --- QVariant ----------------------------------------------------------------

QString nimqt_variant_type_name(const QVariant v) {
  return QString::fromUtf8(v.typeName());
}

// --- Connection helpers ------------------------------------------------------

bool nimqt_connection_is_valid(const QMetaObject::Connection c) {
  return bool(c);
}

// --- QStringList -> QVariantList convenience ---------------------------------

QVariant nimqt_stringlist_to_variant(const QStringList l) {
  return QVariant(l);
}

// --- QGuiApplication bootstrap ----------------------------------------------

static int        g_argc = 1;
static char       g_argv0[] = "nimqt-app";
static char*      g_argv[2] = { g_argv0, nullptr };
static QGuiApplication* g_app = nullptr;

QGuiApplication* nimqt_qguiapp_new() {
  if (!g_app) {
    g_app = new QGuiApplication(g_argc, g_argv);
  }
  return g_app;
}

int nimqt_qguiapp_argc() { return g_argc; }
char** nimqt_qguiapp_argv() { return g_argv; }

// --- QQmlError lists ---------------------------------------------------------

QStringList nimqt_component_errors(QQmlComponent* c) {
  QStringList out;
  if (!c) return out;
  const QList<QQmlError> errs = c->errors();
  for (const QQmlError& e : errs)
    out.append(e.toString());
  return out;
}

QStringList nimqt_view_errors(QQuickView* v) {
  QStringList out;
  if (!v) return out;
  const QList<QQmlError> errs = v->errors();
  for (const QQmlError& e : errs)
    out.append(e.toString());
  return out;
}

// --- QQmlIncubator async creation -------------------------------------------
// Opaque handle: [QQmlIncubator-derived, result ptr]. poll() pumps nothing
// itself; the Qt event loop drives incubation. States: 0 loading, 1 ready,
// 2 error.

struct NimqtIncubator : public QQmlIncubator {
  explicit NimqtIncubator(IncubationMode mode = Asynchronous)
    : QQmlIncubator(mode) {}
  void setInitialState(QObject* o) override {
    m_result = o;
    QQmlIncubator::setInitialState(o);
  }
  void statusChanged(Status st) override {
    m_done = (st == Ready || st == Error);
    QQmlIncubator::statusChanged(st);
  }
  QObject* m_result = nullptr;
  bool     m_done = false;
};

void* nimqt_incubator_start(QQmlComponent* c, QQmlContext* ctx) {
  if (!c) return nullptr;
  auto* inc = new NimqtIncubator(QQmlIncubator::Asynchronous);
  c->create(*inc, ctx);
  return static_cast<void*>(inc);
}

int nimqt_incubator_poll(void* h) {
  auto* inc = static_cast<NimqtIncubator*>(h);
  if (!inc) return 2;
  switch (inc->status()) {
    case QQmlIncubator::Ready:  return 1;
    case QQmlIncubator::Error:  return 2;
    default:                    return 0;
  }
}

QObject* nimqt_incubator_result(void* h) {
  auto* inc = static_cast<NimqtIncubator*>(h);
  return inc ? inc->object() : nullptr;
}

QObject* nimqt_incubator_initial(void* h) {
  auto* inc = static_cast<NimqtIncubator*>(h);
  return inc ? inc->m_result : nullptr;
}

bool nimqt_incubator_done(void* h) {
  auto* inc = static_cast<NimqtIncubator*>(h);
  return inc ? inc->m_done : true;
}

QStringList nimqt_incubator_errors(void* h) {
  QStringList out;
  auto* inc = static_cast<NimqtIncubator*>(h);
  if (!inc) return out;
  const QList<QQmlError> errs = inc->errors();
  for (const QQmlError& e : errs)
    out.append(e.toString());
  return out;
}

void nimqt_incubator_free(void* h) {
  delete static_cast<NimqtIncubator*>(h);
}

// --- QList<QObject*> for QQmlApplicationEngine -------------------------------

typedef QList<QObject*> QObjectListRaw;

QList<QObject*> nimqt_appeng_root_objects(QQmlApplicationEngine* e) {
  if (!e) return QList<QObject*>();
  return e->rootObjects();
}

// --- QJSValue call / construct / array helpers -------------------------------

QJSValue nimqt_jsengine_new_array(QJSEngine* e, quint32 len) {
  return e ? e->newArray(len) : QJSValue();
}


// Pointer-array variant: C++ performs proper QJSValue copy-construction
// for each argument (Nim must not store bycopy Qt values in seqs).
QJSValue nimqt_qjsvalue_call_ptrs(const QJSValue* j, QJSValue* const* args, int n) {
  if (!j) return QJSValue();
  if (n <= 0 || args == nullptr)
    return j->call();
  QJSValueList list;
  for (int i = 0; i < n; ++i)
    if (args[i]) list.append(*args[i]);
  return j->call(list);
}

QJSValue nimqt_qjsvalue_construct_ptrs(const QJSValue* j, QJSValue* const* args, int n) {
  if (!j) return QJSValue();
  if (n <= 0 || args == nullptr)
    return j->callAsConstructor();
  QJSValueList list;
  for (int i = 0; i < n; ++i)
    if (args[i]) list.append(*args[i]);
  return j->callAsConstructor(list);
}

QJSValue nimqt_qjsvalue_call(const QJSValue j, QJSValue* args, int n) {
  if (n <= 0 || args == nullptr)
    return j.call();
  return j.call(QJSValueList(args, args + n));
}

QJSValue nimqt_qjsvalue_construct(const QJSValue j, QJSValue* args, int n) {
  if (n <= 0 || args == nullptr)
    return j.callAsConstructor();
  return j.callAsConstructor(QJSValueList(args, args + n));
}

QJSValue nimqt_qjsvalue_call_p(const QJSValue* j, QJSValue* args, int n) {
  return nimqt_qjsvalue_call(j ? *j : QJSValue(), args, n);
}

QJSValue nimqt_qjsvalue_construct_p(const QJSValue* j, QJSValue* args, int n) {
  return nimqt_qjsvalue_construct(j ? *j : QJSValue(), args, n);
}

// --- Grab results ------------------------------------------------------------

QImage nimqt_grabresult_image(QQuickItemGrabResult* r) {
  return r ? r->image() : QImage();
}

QImage nimqt_quickwindow_grab(QQuickWindow* w) {
  return w ? w->grabWindow() : QImage();
}

// --- Misc --------------------------------------------------------------------

QString nimqt_item_cursor_name(QQuickItem* i) {
  if (!i) return QString();
  switch (i->cursor().shape()) {
    case Qt::BlankCursor:      return QString::fromUtf8("blank");
    case Qt::PointingHandCursor: return QString::fromUtf8("pointing");
    case Qt::IBeamCursor:      return QString::fromUtf8("ibeam");
    case Qt::WaitCursor:       return QString::fromUtf8("wait");
    case Qt::CrossCursor:      return QString::fromUtf8("cross");
    default:                   return QString::fromUtf8("arrow");
  }
}

// From dynmeta.cpp: detect whether an exposed object's slot really ran.
int  nimqt_dynexpose_last_invoked(void* o);
void nimqt_dynexpose_reset_last_invoked(void* o);
bool nimqt_is_dynexpose(QObject* o);

// --- Dynamic method invocation ----------------------------------------------
//
// Primary path: the string-based QMetaObject::invokeMethod(member, ...) with
// legacy Q_ARG/Q_RETURN_ARG. Qt 6.9+ removed old-style args from the
// *instance* QMetaMethod::invoke templates, but this static overload remains
// the supported way to invoke dynamically-named members (incl. QML
// VME/script-defined functions). Arguments are converted to each declared
// parameter metatype first (mirroring the QML engine), then passed as
// QVariant-typed generic arguments.
//
// Fallback: QQmlExpression evaluation when invokeMethod reports failure but
// a matching method exists (covers engine-version differences).

bool nimqt_invoke_method_c(QObject* o, const char* name, QVariant* args,
                           int argc, QVariant* retOut);
// --- Debug helpers for invoke diagnostics ------------------------------------

QString nimqt_mm_return_name(const QMetaMethod mm) {
  return QString::fromUtf8(mm.returnMetaType().name());
}

bool nimqt_invoke_method(QObject* o, const char* name, QVariant* args,
                         int argc, QVariant* retOut);
int nimqt_invoke_method_dbg(QObject* o, const char* name, QVariant* args,
                            int argc, QVariant* retOut) {
  // 0 = ok, 1 = no method, 2 = invoke returned false, 3 = returnsValue false
  if (!nimqt_invoke_method(o, name, args, argc, retOut)) {
    const QMetaObject* mo = o->metaObject();
    int idx = -1;
    for (int m = 0; m < mo->methodCount() && idx < 0; ++m) {
      QMetaMethod cand = mo->method(m);
      if (cand.name() == QByteArray(name) && cand.parameterCount() == argc)
        idx = m;
    }
    if (idx < 0) return 1;
    QMetaMethod mm = mo->method(idx);
    const QMetaType rt = mm.returnMetaType();
    if (!rt.isValid() || rt == QMetaType::fromType<void>())
      return 3;
    return 2;
  }
  return 0;
}

// --- Wrapper-level dispose helpers -------------------------------------------

void nimqt_engine_free(QQmlEngine* e) { delete e; }

void nimqt_component_dispose(QQmlComponent* c) { delete c; }

void nimqt_view_close_and_free(QQuickView* v) {
  if (!v) return;
  v->close();
  delete v;
}

NIMQT_END

// Implemented with C++ linkage (uses template-based Q_ARG macros).
bool nimqt_invoke_method(QObject* o, const char* name, QVariant* args,
                         int argc, QVariant* retOut) {
  if (!o || !name) return false;
  const QMetaObject* mo = o->metaObject();

  // Find an overload: exact typed signature first, then name+arity.
  int idx = -1;
  {
    QByteArray typed(name);
    typed += '(';
    for (int i = 0; i < argc; ++i) {
      if (i) typed += ',';
      typed += QMetaType(args[i].metaType()).name();
    }
    typed += ')';
    idx = mo->indexOfMethod(typed.constData());
  }
  if (idx < 0) {
    for (int m = 0; m < mo->methodCount() && idx < 0; ++m) {
      QMetaMethod cand = mo->method(m);
      if (cand.name() != QByteArray(name)) continue;
      if (cand.parameterCount() != argc) continue;
      idx = m;
    }
  }
  if (idx < 0) return false;

  const QMetaMethod mm = mo->method(idx);

  // Convert arguments into exact declared parameter types.
  QVariant store[10];
  const int n = qBound(0, argc, 10);
  for (int i = 0; i < n && i < argc; ++i) {
    store[i] = args[i];
    QMetaType pt = mm.parameterMetaType(i);
    if (!pt.isValid() || pt == store[i].metaType()) continue;
    // Never wrap into QVariant-of-X: QML/VME wants the bare value;
    // double-convert produced QVariant(QVariant(v)) and NaNs.
    if (pt == QMetaType::fromType<QVariant>()) continue;
    if (!store[i].convert(pt))
      qWarning("nimqt_invoke_method: arg %d cannot convert %s -> %s",
               i, store[i].typeName(), pt.name());
  }

  const QMetaType rt = mm.returnMetaType();
  const bool returnsValue =
      rt.isValid() && rt != QMetaType::fromType<void>();
  QVariant ret;
  bool ok = false;

#define NIMQT_G(i) Q_ARG(QVariant, store[i])

// Two full expansions: void-return must not carry a return argument.
#define NIMQT_CASE_RET(N, ...)                                                 \
  case N: ok = QMetaObject::invokeMethod(o, name, Qt::DirectConnection,        \
            Q_RETURN_ARG(QVariant, ret), ##__VA_ARGS__);                       \
          break;
#define NIMQT_CASE_VOID(N, ...)                                                \
  case N: ok = QMetaObject::invokeMethod(o, name, Qt::DirectConnection,        \
            ##__VA_ARGS__);                                                    \
          break;

  if (returnsValue) {
    switch (n) {
    case 0: ok = QMetaObject::invokeMethod(o, name, Qt::DirectConnection, Q_RETURN_ARG(QVariant, ret)); break;
    NIMQT_CASE_RET(1, NIMQT_G(0))
    NIMQT_CASE_RET(2, NIMQT_G(0), NIMQT_G(1))
    NIMQT_CASE_RET(3, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2))
    NIMQT_CASE_RET(4, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3))
    NIMQT_CASE_RET(5, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4))
    NIMQT_CASE_RET(6, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5))
    NIMQT_CASE_RET(7, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5), NIMQT_G(6))
    NIMQT_CASE_RET(8, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5), NIMQT_G(6), NIMQT_G(7))
    }
  } else {
    switch (n) {
    case 0: ok = QMetaObject::invokeMethod(o, name, Qt::DirectConnection); break;
    NIMQT_CASE_VOID(1, NIMQT_G(0))
    NIMQT_CASE_VOID(2, NIMQT_G(0), NIMQT_G(1))
    NIMQT_CASE_VOID(3, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2))
    NIMQT_CASE_VOID(4, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3))
    NIMQT_CASE_VOID(5, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4))
    NIMQT_CASE_VOID(6, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5))
    NIMQT_CASE_VOID(7, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5), NIMQT_G(6))
    NIMQT_CASE_VOID(8, NIMQT_G(0), NIMQT_G(1), NIMQT_G(2), NIMQT_G(3), NIMQT_G(4), NIMQT_G(5), NIMQT_G(6), NIMQT_G(7))
    }
  }
#undef NIMQT_CASE_RET
#undef NIMQT_CASE_VOID
#undef NIMQT_G

  if (ok && returnsValue && retOut)
    *retOut = ret;
  if (!ok && nimqt_is_dynexpose(o)) {
    // Qt reports failure for dynamic-MO methods whose QVariant return type
    // was resolved at build time; the slot may still have run and written
    // the return through Q_RETURN_ARG storage (verified empirically). Trust
    // the metacall-side receipt.
    if (nimqt_dynexpose_last_invoked(o) >= 0) {
      nimqt_dynexpose_reset_last_invoked(o);
      if (returnsValue && retOut)
        *retOut = ret;
      return true;
    }
    nimqt_dynexpose_reset_last_invoked(o);
  }
  if (ok)
    return true;

  // ---- Fallback: QQmlExpression (script functions on QML objects) --------
  {  // fallback scope (applies to void methods too: errors are logged)
    QString expr = QString::fromUtf8(name) + "(";
    QStringList params;
    for (int i = 0; i < n; ++i) {
      QString lit;
      const QVariant& v = args[i];
      switch (v.metaType().id()) {
        case QMetaType::Double:
        case QMetaType::Int:
        case QMetaType::LongLong: lit = v.toString(); break;
        case QMetaType::Bool:     lit = v.toBool() ? "true" : "false"; break;
        default: {
          // Escape backslashes first, then quotes; flatten newlines so the
          // generated single-line expression stays syntactic.
          QString s = v.toString();
          s.replace("\\", "\\\\");
          s.replace("'", "\\'");
          s.replace("\n", "\\n");
          s.remove('\r');
          lit = "'" + s + "'";
          break;
        }
      }
      params << lit;
    }
    expr += params.join(", ") + ")";
    QQmlContext* ctx = QQmlEngine::contextForObject(o);
    if (ctx && ctx->engine()) {
      QQmlExpression e(ctx, o, expr);
      bool undefinedResult = false;
      QVariant exprRet = e.evaluate(&undefinedResult);
      if (!e.hasError()) {
        if (retOut) *retOut = exprRet;
        return true;
      }
      qWarning("nimqt: QQmlExpression fallback failed: %s",
               e.error().toString().toUtf8().constData());
    }
  }
  return false;
}

// C-linkage wrapper consumed by Nim (implementation above has C++ linkage
// because Q_ARG expands to template code).
extern "C" bool nimqt_invoke_method_c(QObject* o, const char* name,
                                      QVariant* args, int argc,
                                      QVariant* retOut) {
  return nimqt_invoke_method(o, name, args, argc, retOut);
}

// Pointer-based entry: C++ copy-constructs each argument from Nim's
// storage (never bitwise-copy QVariant across the Nim/C++ boundary).
extern "C" bool nimqt_invoke_method_p(QObject* o, const char* name,
                                      QVariant* const* args, int argc,
                                      QVariant* retOut) {
  if (argc > 0 && args == nullptr) return false;
  QVariant copied[10];
  const int n = qBound(0, argc, 10);
  for (int i = 0; i < n; ++i)
    if (args[i]) copied[i] = *args[i];
  return nimqt_invoke_method(o, name, n ? copied : nullptr, n, retOut);
}
