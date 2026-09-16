// SPDX-License-Identifier: GPL-2.0-or-later
#include <effect/offscreeneffect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <core/output.h>
#include <core/pixelgrid.h>
#include <x11window.h>
#include <utils/xcbutils.h>
#include <scene/borderradius.h>
#include <opengl/glutils.h>
#include <KConfigGroup>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace KWin {

class WeChatGlassLive final : public OffscreenEffect
{
    Q_OBJECT
public:
    WeChatGlassLive()
    {
        effects->makeOpenGLContextCurrent();
        m_shader = ShaderManager::instance()->generateShaderFromFile(
            ShaderTrait::MapTexture, {}, QStringLiteral(":/wechat-glass-live-v5/glass.frag"));
        connect(effects, &EffectsHandler::windowDeleted, this, [this](EffectWindow *w) {
            // windowClosed starts the close animation. Keep the redirection
            // until KWin releases the window; do not extend its lifetime here.
            restoreBlur(w);
            // OffscreenEffect handles destruction of its own texture.
            m_windows.remove(w);
        });
        reconfigure(ReconfigureAll);
    }

    ~WeChatGlassLive() override
    {
        clearWindows();
        effects->makeOpenGLContextCurrent();
    }

    int requestedEffectChainPosition() const override { return 99; }

    bool isActive() const override
    {
        if (!m_enabled || !m_shader
            || effects->hasActiveFullScreenEffect()) {
            return false;
        }
        const auto windows = effects->stackingOrder();
        return std::any_of(windows.cbegin(), windows.cend(), [this](EffectWindow *w) {
            return matches(w);
        });
    }

    void reconfigure(ReconfigureFlags) override
    {
        const auto settings = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
        settings->reparseConfiguration();
        KConfigGroup config(settings, QStringLiteral("Effect-wechat-glass-live"));
        m_enabled = config.readEntry("Enabled", true);
        m_opacity = std::clamp(config.readEntry("BackgroundOpacity", 0.52), 0.1, 1.0);
        m_barSize = QVector2D(config.readEntry("NavigationWidth", 60.8),
                             config.readEntry("TitleHeight", 32.8));
        m_tolerance = std::clamp(config.readEntry("MatchTolerance", 0.025), 0.006, 0.15);
        m_cornerRadius = std::clamp(config.readEntry("CornerRadius", 16.0), 0.0, 64.0);
        clearWindows();
        effects->addRepaintFull();
    }

    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override
    {
        if (matches(w)) {
            // A closing X11Window has already released its X client handle.
            // Better Blur DX retains the last region until windowDeleted.
            if (!w->isDeleted()) {
                updateBlur(w);
            }
            if (!m_windows.contains(w)) {
                // OffscreenEffect captures during painting, and invalidates its
                // texture on actual surface damage. AnimationEffect's Shader
                // attribute instead uses a static CrossFadeEffect snapshot.
                redirect(w);
                setShader(w, m_shader.get());
                m_windows.insert(w);
            }
            // Let the compositor paint the backdrop under the two transparent
            // bars, without changing input, visibility refs, or window opacity.
            data.setTranslucent();
        } else {
            detach(w);
        }
        effects->prePaintWindow(view, w, data);
    }

    void apply(EffectWindow *w, int, WindowPaintData &, WindowQuadList &) override
    {
        const qreal scale = w->screen()->scale();
        const auto frame = snapToPixels(w->frameGeometry(), scale);
        const auto expanded = snapToPixels(w->expandedGeometry(), scale);
        ShaderBinder binder(m_shader.get());
        m_shader->setUniform("uFrameSize", QVector2D(frame.width(), frame.height()));
        m_shader->setUniform("uExpandedSize", QVector2D(expanded.width(), expanded.height()));
        m_shader->setUniform("uExpandedOffset", QVector2D(expanded.x() - frame.x(), expanded.y() - frame.y()));
        m_shader->setUniform("uBarSize", m_barSize);
        m_shader->setUniform("uOpacity", float(m_opacity));
        m_shader->setUniform("uTolerance", float(m_tolerance));
        m_shader->setUniform("uCornerRadii", cornerRadii(w));
        ++m_paintedFrames;
    }

    QString debug(const QString &) const override
    {
        return QString::fromUtf8(QJsonDocument(QJsonObject{
            {"renderer", "OffscreenEffect (live window damage)"},
            {"version", "0.5.0"},
            {"enabled", m_enabled},
            {"shader_valid", bool(m_shader)},
            {"redirected_windows", int(m_windows.size())},
            {"windows_with_blur_region", int(m_blur.size())},
            {"blur_scope", "rounded title and navigation bars; no popup matching"},
            {"painted_frames", double(m_paintedFrames)},
            {"active", isActive()}
        }).toJson(QJsonDocument::Compact));
    }

private:
    bool matches(EffectWindow *w) const
    {
        // Only retain windows we already processed while they were live.
        // Closing windows no longer satisfy the ordinary matching conditions.
        if (w->isDeleted()) {
            return m_windows.contains(w);
        }
        const auto classes = w->windowClass().split(QLatin1Char(' '));
        static const QRegularExpression caption(QStringLiteral("^(微信|WeChat|Weixin)(?:\\s*\\(\\d+\\))?$"),
                                                 QRegularExpression::CaseInsensitiveOption);
        return (classes.contains(QStringLiteral("wechat")) || classes.contains(QStringLiteral("com.tencent.wechat"), Qt::CaseInsensitive))
            && w->isX11Client() && w->isNormalWindow() && !w->isDialog() && !w->isPopupWindow()
            && !w->window()->isTransient()
            && w->isVisible() && !w->isMinimized()
            && w->isOnCurrentDesktop() && w->isOnCurrentActivity()
            && w->width() >= 640 && w->height() >= 450
            && caption.match(w->caption()).hasMatch();
    }

    void detach(EffectWindow *w)
    {
        restoreBlur(w);
        if (m_windows.remove(w)) {
            unredirect(w);
        }
    }

    void clearWindows()
    {
        const auto windows = m_windows;
        for (auto *w : windows) {
            detach(w);
        }
    }

    QVector4D cornerRadii(EffectWindow *w) const
    {
        auto r = w->window()->borderRadius();
        if (r.isNull() && !w->isFullScreen() && w->window()->maximizeMode() != MaximizeFull) {
            r = BorderRadius(m_cornerRadius);
        }
        const float limit = std::min(w->width(), w->height()) * 0.5;
        return QVector4D(std::min(float(r.topLeft()), limit), std::min(float(r.topRight()), limit),
                         std::min(float(r.bottomLeft()), limit), std::min(float(r.bottomRight()), limit));
    }

    struct BlurState {
        xcb_window_t window;
        xcb_atom_t atom;
        xcb_atom_t originalType;
        uint8_t originalFormat;
        QByteArray original;
        QVector<uint32_t> applied;
        QSize size;
        QVector4D radii;
    };

    void updateBlur(EffectWindow *w)
    {
        auto *client = qobject_cast<X11Window *>(w->window());
        auto *connection = effects->xcbConnection();
        if (!client || !connection) return;
        if (!m_blur.contains(w)) {
            // Hiding to the tray leaves the X window alive. Reopening it can
            // create a new EffectWindow before the old close animation ends.
            // Transfer ownership so the old window cannot restore our property
            // over the reopened window, or mistake our region for the original.
            for (auto it = m_blur.begin(); it != m_blur.end(); ++it) {
                if (it.key()->isDeleted() && it->window == client->window()) {
                    const auto state = it.value();
                    m_blur.erase(it);
                    m_blur.insert(w, state);
                    break;
                }
            }
        }
        if (!m_blur.contains(w)) {
            const QByteArray name("_KDE_NET_WM_BLUR_BEHIND_REGION");
            auto *atom = xcb_intern_atom_reply(connection, xcb_intern_atom(connection, false, name.size(), name.constData()), nullptr);
            if (!atom) return;
            BlurState state{};
            state.window = client->window();
            state.atom = atom->atom;
            free(atom);
            auto *property = xcb_get_property_reply(connection, xcb_get_property(connection, false, state.window, state.atom, XCB_GET_PROPERTY_TYPE_ANY, 0, 32768), nullptr);
            if (!property) return;
            state.originalType = property->type;
            state.originalFormat = property->format;
            state.original = QByteArray(static_cast<const char *>(xcb_get_property_value(property)), xcb_get_property_value_length(property));
            free(property);
            m_blur.insert(w, state);
        }
        auto &state = m_blur[w];
        const auto size = Xcb::toXNative(w->size());
        const auto radii = cornerRadii(w);
        if (state.size == size && state.radii == radii) return;
        state.size = size;
        state.radii = radii;
        const double scale = double(size.width()) / w->width();
        const int title = std::ceil(m_barSize.y() * scale);
        const int nav = std::ceil(m_barSize.x() * scale);
        QVector<uint32_t> rects;
        // One device-pixel inset keeps blur out of the antialiased outer edge.
        // Adjacent scanlines are merged so only the corner arcs add rectangles.
        for (int y = 1; y < size.height() - 1; ++y) {
            const auto inset = [&](double top, double bottom) {
                const double r = y + 0.5 < top ? top : y + 0.5 > size.height() - bottom ? bottom : 0.0;
                if (r <= 1.0) return 1;
                const double dy = y + 0.5 < top ? top - y - 0.5 : y + 0.5 - (size.height() - bottom);
                return std::max(1, int(std::ceil(r - std::sqrt(std::max(0.0, (r - 1) * (r - 1) - dy * dy)) - 0.5)));
            };
            const int left = inset(radii.x() * scale, radii.z() * scale);
            int right = size.width() - inset(radii.y() * scale, radii.w() * scale);
            if (y >= title) right = std::min(right, nav);
            if (right <= left) continue;
            const auto n = rects.size();
            if (n && rects[n-4] == uint32_t(left) && rects[n-2] == uint32_t(right-left)
                && rects[n-3] + rects[n-1] == uint32_t(y)) {
                ++rects[n-1];
            } else {
                rects << uint32_t(left) << uint32_t(y) << uint32_t(right-left) << uint32_t(1);
            }
        }
        state.applied = rects;
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, state.window, state.atom,
                            XCB_ATOM_CARDINAL, 32, rects.size(), rects.constData());
        xcb_flush(connection);
    }

    void restoreBlur(EffectWindow *w)
    {
        auto it = m_blur.find(w);
        if (it == m_blur.end()) return;
        const auto state = it.value();
        m_blur.erase(it);
        auto *connection = effects->xcbConnection();
        if (!connection) return;
        // isDeleted() describes the KWin wrapper, not necessarily the X window:
        // a hidden tray window still exists. A destroyed X window simply makes
        // the checked property query below fail without a restore operation.
        // Preserve a newer blur request written by the application itself.
        auto *current = xcb_get_property_reply(connection, xcb_get_property(connection, false, state.window, state.atom, XCB_ATOM_CARDINAL, 0, 32768), nullptr);
        if (!current) return;
        const QByteArray value(static_cast<const char *>(xcb_get_property_value(current)), xcb_get_property_value_length(current));
        free(current);
        const QByteArray applied(reinterpret_cast<const char *>(state.applied.constData()), state.applied.size() * sizeof(uint32_t));
        if (value != applied) return;
        if (state.originalType != XCB_ATOM_NONE && state.originalFormat) {
            xcb_change_property(connection, XCB_PROP_MODE_REPLACE, state.window, state.atom,
                                state.originalType, state.originalFormat,
                                state.original.size() / (state.originalFormat / 8), state.original.constData());
        } else {
            xcb_delete_property(connection, state.window, state.atom);
        }
        xcb_flush(connection);
    }

    bool m_enabled = true;
    double m_opacity = 0.52;
    double m_tolerance = 0.025;
    double m_cornerRadius = 16.0;
    QVector2D m_barSize;
    quint64 m_paintedFrames = 0;
    QSet<EffectWindow *> m_windows;
    QHash<EffectWindow *, BlurState> m_blur;
    std::unique_ptr<GLShader> m_shader;
};

KWIN_EFFECT_FACTORY_SUPPORTED(WeChatGlassLive, "metadata.json", return OffscreenEffect::supported();)

} // namespace KWin

#include "glass.moc"
