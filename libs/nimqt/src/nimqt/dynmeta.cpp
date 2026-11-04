// nimqt — dynmeta.cpp: dynamic metaobject backend.
//
// Implements the dyntrap_* / dynexpose_* contract declared in signals.nim,
// backed by Qt's QMetaObjectBuilder (QtCore private API, <private/qmetaobjectbuilder_p.h>).
//
// Design:
//  * All dynamically-declared properties, signal parameters and slot
//    parameters use the metatype `QVariant`. QML unwraps/wraps QVariant
//    transparently, so JS sees native values; Nim hooks see Variants.
//  * DynTrap: per-connection receiver object whose dynamic metaobject holds
//    ONE slot with the exact signature (name + QVariant arity) of the signal
//    being connected. Connected via the QMetaMethod/QMetaMethod overload so
//    Qt performs matched-argument delivery.
//  * DynExpose: one object = one dynamic metaobject declaring properties,
//    signals, invokables. Methods added in fixed order: slots first, then
//    signals (defines relative indexing in qt_metacall).

#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QVariant>
#include <QMetaObject>
#include <QMetaMethod>
#include <QMetaType>
#include <QMetaProperty>
#include <QObject>
#include <QList>

#include <private/qmetaobjectbuilder_p.h>

namespace {

// ---------------------------------------------------------------------------
// Shared base: hosts a dynamic metaobject and dispatches relative-id calls.
// ---------------------------------------------------------------------------

struct TrapCallbacks {
  void* env = nullptr;
  void (*invokeFn)(void* env, int argc, QVariant* args) = nullptr;
};

class DynTrapImpl : public QObject {
public:
  explicit DynTrapImpl(TrapCallbacks cb) : m_cb(cb) {}

  void setDynamicMeta(QMetaObject* mo) {
    m_mo = mo;
  }

  const QMetaObject* metaObject() const override {
    return m_mo ? m_mo : &QObject::staticMetaObject;
  }

  int qt_metacall(QMetaObject::Call c, int id, void** a) override {
    id = QObject::qt_metacall(c, id, a);
    if (id < 0) return id;
    if (c == QMetaObject::InvokeMetaMethod && id == 0) {
      // Our single dynamic slot: args arrive as QVariant* (uniform type).
      QVariant args[10];
      const int n = m_paramCount < 10 ? m_paramCount : 10;
      for (int i = 0; i < n; ++i)
        args[i] = *reinterpret_cast<QVariant*>(a[i + 1]);
      if (m_cb.invokeFn)
        m_cb.invokeFn(m_cb.env, n, args);
      return --id;
    }
    return id;
  }

  void setParamCount(int n) { m_paramCount = n; }

private:
  TrapCallbacks m_cb;
  QMetaObject* m_mo = nullptr;
  int m_paramCount = 0;
};

// ---------------------------------------------------------------------------
// DynExpose: full property/signal/invokable surface routed to Nim.
// ---------------------------------------------------------------------------

struct ExposeCallbacks {
  void* env = nullptr;
  void (*readFn)(void* env, int propId, QVariant* out) = nullptr;
  bool (*writeFn)(void* env, int propId, QVariant* in) = nullptr;
  bool (*invokeFn)(void* env, int slotId, QVariant* args, int argc,
                   QVariant* ret) = nullptr;
};

class DynExposeImpl : public QObject {
public:
  DynExposeImpl(ExposeCallbacks cb, int slotCount, int signalCount)
      : m_cb(cb), m_slotCount(slotCount), m_signalCount(signalCount) {}

  void setDynamicMeta(QMetaObject* mo) { m_mo = mo; }

  const QMetaObject* metaObject() const override {
    return m_mo ? m_mo : &QObject::staticMetaObject;
  }

  bool emitSignalByName(const QByteArray& nameOrSig, QVariant* args, int argc) {
    if (!m_mo) return false;
    int abs = m_mo->indexOfSignal(nameOrSig.constData());
    if (abs < 0) {
      // Bare-name fallback: first signal with this name.
      const int off = m_mo->methodOffset();
      for (int i = off; i < m_mo->methodCount(); ++i) {
        const QMetaMethod m = m_mo->method(i);
        if (m.methodType() == QMetaMethod::Signal && m.name() == nameOrSig) {
          abs = i;
          break;
        }
      }
    }
    if (abs < 0) return false;

    const QMetaMethod sig = m_mo->method(abs);
    const int pc = sig.parameterCount();
    if (argc < pc) return false;

    // All dynamic-signal parameters are declared QVariant, so each slot
    // entry must point AT a QVariant object, not at its contents.
    void* stack[12] = {nullptr};
    QVariant boxed[10];
    const int nb = qMin(pc, 10);
    for (int i = 0; i < nb; ++i)
      boxed[i] = args[i];
    for (int i = 0; i < nb && i + 1 < 12; ++i)
      stack[i + 1] = &boxed[i];

    // Index relative to the metaobject's own methods (moc convention).
    QMetaObject::activate(this, m_mo, abs - m_mo->methodOffset(), stack);
    return true;
  }

  int qt_metacall(QMetaObject::Call c, int id, void** a) override {
    id = QObject::qt_metacall(c, id, a);
    if (id < 0) return id;

    if (c == QMetaObject::ReadProperty) {
      if (id >= 0 && id < m_propCount && m_cb.readFn) {
        m_cb.readFn(m_cb.env, id, reinterpret_cast<QVariant*>(a[0]));
      }
      return --id;
    }
    if (c == QMetaObject::WriteProperty) {
      if (id >= 0 && id < m_propCount) {
        if (m_cb.writeFn) {
          QVariant v = *reinterpret_cast<QVariant*>(a[0]);
          if (!m_cb.writeFn(m_cb.env, id, &v)) return id;
        }
      }
      return --id;
    }
    if (c == QMetaObject::InvokeMetaMethod) {
      if (id >= 0 && id < m_slotCount) {
        QVariant args[10];
        QVariant ret;
        // Parameter count from the metaobject itself.
        const QMetaMethod mm = m_mo->method(m_mo->methodOffset() + id);
        const int n = qMin(mm.parameterCount(), 10);
        for (int i = 0; i < n; ++i) {
          if (a[i + 1])
            args[i] = *reinterpret_cast<QVariant*>(a[i + 1]);
        }
        lastInvokedSlot = id;
        bool ok = true;
        if (m_cb.invokeFn)
          ok = m_cb.invokeFn(m_cb.env, id, args, n, &ret);
        // Return value (all our invokables return QVariant or void).
        if (mm.returnMetaType().isValid() &&
            mm.returnMetaType() != QMetaType::fromType<void>() && a[0])
          *reinterpret_cast<QVariant*>(a[0]) = ret;
        return --id;
      }
      id -= m_slotCount;
      if (id >= 0 && id < m_signalCount)
        return --id;  // internal signal emission: nothing to do
      return id;
    }
    return id;
  }

  void setPropCount(int n) { m_propCount = n; }

  // Set inside qt_metacall so callers can detect that a dynamic slot really
  // executed even when string-based invokeMethod reports failure (Qt returns
  // false for dynamic-MO QVariant-return methods whose metatype was resolved
  // at build time rather than from the registry).
  int lastInvokedSlot = -1;

private:
  ExposeCallbacks m_cb;
  QMetaObject* m_mo = nullptr;
  int m_slotCount = 0;
  int m_signalCount = 0;
  int m_propCount = 0;
};

} // namespace

// ---------------------------------------------------------------------------
// extern "C" bridge consumed by signals.nim
// ---------------------------------------------------------------------------


// --- Trap liveness registry (sender-death safety) ---------------------------
// dyntrap objects are parented to their sender QObject; when the sender dies
// Qt destroys the trap. Nim-side ConnRecords then hold dangling pointers.
// We track live traps here so Nim can check before freeing.
#include <unordered_set>
static std::unordered_set<void*> g_liveTraps;

extern "C" {

// ---- dyntrap ----

void* nimqt_dyntrap_create(void (*invokeFn)(void*, int, QVariant*),
                           void* env) {
  TrapCallbacks cb;
  cb.env = env;
  cb.invokeFn = invokeFn;
  auto* t = new DynTrapImpl(cb);
  g_liveTraps.insert(t);
  return t;
}

int nimqt_dyntrap_is_alive(void* trap) {
  return g_liveTraps.count(trap) ? 1 : 0;
}

int nimqt_dyntrap_build_matching_slot(void* trap, QObject* sender,
                                      int signalIndex) {
  auto* t = static_cast<DynTrapImpl*>(trap);
  if (!t || !sender || signalIndex < 0) return -1;
  const QMetaObject* smo = sender->metaObject();
  if (signalIndex >= smo->methodCount()) return -1;
  const QMetaMethod sig = smo->method(signalIndex);

  QMetaObjectBuilder b;
  b.setSuperClass(&QObject::staticMetaObject);
  b.setClassName("nimqt_DynTrap");

  // One slot mirroring the signal: same name, QVariant params, void return.
  QList<QByteArray> varParams;
  for (int i = 0; i < sig.parameterCount(); ++i)
    varParams.append("QVariant");
  QByteArray fsig = sig.name() + '(' + varParams.join(',') + ')';
  QMetaMethodBuilder m = b.addMethod(fsig);
  m.setReturnType("void");
  m.setAttributes(QMetaMethod::Scriptable);

  QMetaObject* mo = b.toMetaObject();
  t->setDynamicMeta(mo);
  t->setParamCount(sig.parameterCount());
  return 0; // relative slot index inside the dynamic metaobject
}

void* nimqt_dyntrap_connect(QObject* sender, int signalIndex, void* trap,
                            int slotIndex) {
  auto* t = static_cast<DynTrapImpl*>(trap);
  if (!t || !sender || signalIndex < 0) return nullptr;
  const QMetaObject* smo = sender->metaObject();
  if (signalIndex >= smo->methodCount()) return nullptr;
  const QMetaObject* tmo = t->metaObject();

  auto* heap = new QMetaObject::Connection();
  *heap = QObject::connect(sender, smo->method(signalIndex), t,
                           tmo->method(tmo->methodOffset() + slotIndex),
                           Qt::AutoConnection);
  if (!*heap) {
    delete heap;
    return nullptr;
  }
  return heap;
}

void nimqt_dyntrap_destroy(void* trap) {
  auto* t = static_cast<DynTrapImpl*>(trap);
  if (!t) return;
  g_liveTraps.erase(trap);
  QObject::disconnect(t, nullptr, nullptr, nullptr);
  delete t;
}

// ---- connection handle ----

bool nimqt_connection_disconnect(void* conn) {
  if (!conn) return false;
  return QObject::disconnect(*static_cast<QMetaObject::Connection*>(conn));
}

void nimqt_connection_free(void* conn) {
  delete static_cast<QMetaObject::Connection*>(conn);
}

int nimqt_find_signal(QObject* o, const char* nameOrSig) {
  if (!o || !nameOrSig) return -1;
  const QMetaObject* mo = o->metaObject();
  int idx = mo->indexOfSignal(nameOrSig);
  if (idx >= 0) return idx;
  const QByteArray want(nameOrSig);
  for (int i = 0; i < mo->methodCount(); ++i) {
    const QMetaMethod m = mo->method(i);
    if (m.methodType() == QMetaMethod::Signal && m.name() == want)
      return i;
  }
  return -1;
}

// ---- dynexpose ----
// Descriptor protocol (newline-separated):
//   props   : "<name>"            (type is always QVariant)
//   signals : "<name>(" [,")" ]   (params all QVariant; arity from commas)
//   slots   : same shape

static QStringList splitLines(const char* text) {
  return QString::fromUtf8(text).split('\n', Qt::SkipEmptyParts);
}

void* nimqt_dynexpose_create(const char* className, const char* propsLines,
                             const char* signalsLines, const char* slotsLines,
                             void (*readFn)(void*, int, QVariant*),
                             bool (*writeFn)(void*, int, QVariant*),
                             bool (*invokeFn)(void*, int, QVariant*, int,
                                              QVariant*),
                             void* env) {
  ExposeCallbacks cb;
  cb.env = env;
  cb.readFn = readFn;
  cb.writeFn = writeFn;
  cb.invokeFn = invokeFn;

  QStringList propNames;
  for (const QString& l : splitLines(propsLines)) {
    const QString t = l.trimmed();
    if (!t.isEmpty()) propNames.append(t);
  }

  struct Meth { QString name; int arity; bool hasRet; };
  QList<Meth> sigs, slotsDescs;
  auto parseMeths = [&](const char* text) {
    QList<Meth> out;
    for (const QString& l : splitLines(text)) {
      QString t = l.trimmed();
      Meth m;
      m.hasRet = false;
      // trailing '!' marks a QVariant return
      if (t.endsWith('!')) { m.hasRet = true; t.chop(1); }
      int lp = t.indexOf('(');
      if (lp < 0) {
        m.name = t;
        m.arity = 0;
      } else {
        m.name = t.left(lp).trimmed();
        int rp = t.lastIndexOf(')');
        QString params = t.mid(lp + 1, rp - lp - 1);
        m.arity = 0;
        for (const QString& p : params.split(',')) {
          if (!p.trimmed().isEmpty()) ++m.arity;
        }
      }
      if (!m.name.isEmpty())
        out.append(m);
    }
    return out;
  };
  sigs = parseMeths(signalsLines);
  slotsDescs = parseMeths(slotsLines);

  QMetaObjectBuilder b;
  b.setSuperClass(&QObject::staticMetaObject);
  b.setClassName(className);

  for (const QString& p : propNames) {
    QMetaPropertyBuilder pp = b.addProperty(p.toUtf8(), "QVariant");
    pp.setReadable(true);
    pp.setWritable(true);
    pp.setStored(false);
  }
  // Fixed order: SLOTS first, then SIGNALS (defines relative indexing).
  for (const Meth& s : slotsDescs) {
    QList<QByteArray> varParams;
    for (int i = 0; i < s.arity; ++i) varParams.append("QVariant");
    QByteArray fsig = s.name.toUtf8() + '(' + varParams.join(',') + ')';
    QMetaMethodBuilder sm = b.addMethod(fsig);
    sm.setReturnType(s.hasRet ? "QVariant" : "void");
    sm.setAttributes(QMetaMethod::Scriptable);
  }
  for (const Meth& s : sigs) {
    QList<QByteArray> varParams;
    for (int i = 0; i < s.arity; ++i) varParams.append("QVariant");
    QByteArray fsig = s.name.toUtf8() + '(' + varParams.join(',') + ')';
    QMetaMethodBuilder sm = b.addSignal(fsig);
    sm.setAttributes(QMetaMethod::Scriptable);
  }

  QMetaObject* mo = b.toMetaObject();

  auto* ex = new DynExposeImpl(cb, slotsDescs.size(), sigs.size());
  ex->setDynamicMeta(mo);
  ex->setPropCount(propNames.size());
  return ex;
}

void nimqt_dynexpose_destroy(void* o) {
  delete static_cast<DynExposeImpl*>(o);
}

bool nimqt_is_dynexpose(QObject* o) {
  if (!o) return false;
  const QMetaObject* mo = o->metaObject();
  // Exposed objects always carry a dynamically-built metaobject whose class
  // differs from every static Qt class; identify them by their qt_metacall
  // ownership: simplest reliable marker is that methodOffset() > 0 while
  // className() was chosen by us (never starts with 'Q').
  return mo->methodOffset() >= mo->superClass()->methodCount()
         && !QByteArray(mo->className()).startsWith('Q');
}

int nimqt_dynexpose_last_invoked(void* o) {
  auto* ex = static_cast<DynExposeImpl*>(o);
  return ex ? ex->lastInvokedSlot : -1;
}

void nimqt_dynexpose_reset_last_invoked(void* o) {
  auto* ex = static_cast<DynExposeImpl*>(o);
  if (ex) ex->lastInvokedSlot = -1;
}

QObject* nimqt_dynexpose_as_qobject(void* o) {
  return static_cast<QObject*>(static_cast<DynExposeImpl*>(o));
}

bool nimqt_dynexpose_emit(void* o, const char* nameOrSig, QVariant* args,
                          int argc) {
  auto* ex = static_cast<DynExposeImpl*>(o);
  return ex ? ex->emitSignalByName(QByteArray(nameOrSig), args, argc) : false;
}

} // extern "C"
