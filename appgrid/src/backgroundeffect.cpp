// SPDX-FileCopyrightText: 2026 AppGrid contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "backgroundeffect.h"

#include "qwayland-ext-background-effect-v1.h"
#include "wayland-ext-background-effect-v1-client-protocol.h"

#include <KConfig>
#include <KConfigGroup>
#include <KConfigWatcher>
#include <KSharedConfig>
#include <KWindowEffects>

#include <QEvent>
#include <QFile>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPlatformSurfaceEvent>
#include <QStandardPaths>
#include <QWindow>
#include <QtWaylandClient/QWaylandClientExtension>

#include <wayland-client-core.h>

namespace
{

bool isWaylandPlatform()
{
    return QGuiApplication::platformName().contains(QStringLiteral("wayland"), Qt::CaseInsensitive);
}

class PlasmaThemeBlurSetting final : public QObject
{
    Q_OBJECT

public:
    explicit PlasmaThemeBlurSetting(QObject *parent = nullptr)
        : QObject(parent)
        , m_plasmaConfig(KSharedConfig::openConfig(QStringLiteral("plasmarc")))
        , m_configWatcher(KConfigWatcher::create(m_plasmaConfig))
    {
        connect(m_configWatcher.data(), &KConfigWatcher::configChanged,
            this, [this](const KConfigGroup &, const QByteArrayList &) {
                reload();
            });
        connect(&m_fileWatcher, &QFileSystemWatcher::fileChanged,
            this, [this](const QString &) {
                reload();
            });
        reload();
    }

    bool allowsBlur() const
    {
        return m_allowsBlur;
    }

Q_SIGNALS:
    void changed();

private:
    void reload()
    {
        m_plasmaConfig->reparseConfiguration();
        const QString themeName = KConfigGroup(m_plasmaConfig, QStringLiteral("Theme"))
                                      .readEntry(QStringLiteral("name"), QStringLiteral("default"));
        const QString relativeBase = QStringLiteral("plasma/desktoptheme/%1/").arg(themeName);
        const QString desktopMetadata = QStandardPaths::locate(
            QStandardPaths::GenericDataLocation, relativeBase + QStringLiteral("metadata.desktop"));
        const QString jsonMetadata = QStandardPaths::locate(
            QStandardPaths::GenericDataLocation, relativeBase + QStringLiteral("metadata.json"));

        bool allowed = true;
        if (!desktopMetadata.isEmpty()) {
            KConfig metadata(desktopMetadata, KConfig::SimpleConfig);
            allowed = KConfigGroup(&metadata, QStringLiteral("BlurBehindEffect"))
                          .readEntry(QStringLiteral("enabled"), true);
        } else if (!jsonMetadata.isEmpty()) {
            QFile file(jsonMetadata);
            if (file.open(QIODevice::ReadOnly)) {
                const QJsonObject blur = QJsonDocument::fromJson(file.readAll())
                                             .object()
                                             .value(QStringLiteral("BlurBehindEffect"))
                                             .toObject();
                if (blur.contains(QStringLiteral("enabled"))) {
                    allowed = blur.value(QStringLiteral("enabled")).toBool(true);
                }
            }
        }

        const QStringList oldPaths = m_fileWatcher.files();
        if (!oldPaths.isEmpty()) {
            m_fileWatcher.removePaths(oldPaths);
        }
        QStringList paths;
        if (!m_plasmaConfig->name().isEmpty() && QFile::exists(m_plasmaConfig->name())) {
            paths.append(m_plasmaConfig->name());
        }
        if (!desktopMetadata.isEmpty()) {
            paths.append(desktopMetadata);
        }
        if (!jsonMetadata.isEmpty()) {
            paths.append(jsonMetadata);
        }
        if (!paths.isEmpty()) {
            m_fileWatcher.addPaths(paths);
        }

        if (m_allowsBlur == allowed) {
            return;
        }
        m_allowsBlur = allowed;
        Q_EMIT changed();
    }

    KSharedConfig::Ptr m_plasmaConfig;
    KConfigWatcher::Ptr m_configWatcher;
    QFileSystemWatcher m_fileWatcher;
    bool m_allowsBlur = true;
};

class BackgroundEffectManager final
    : public QWaylandClientExtensionTemplate<BackgroundEffectManager>
    , public QtWayland::ext_background_effect_manager_v1
{
    Q_OBJECT

public:
    explicit BackgroundEffectManager(QObject *parent = nullptr)
        : QWaylandClientExtensionTemplate<BackgroundEffectManager>(1)
    {
        setParent(parent);
        initialize();
        connect(this, &QWaylandClientExtension::activeChanged, this, [this]() {
            if (!isActive() && m_supportsBlur) {
                m_supportsBlur = false;
            }
            Q_EMIT availabilityChanged();
        });
    }

    bool supportsBlur() const
    {
        return isActive() && m_supportsBlur;
    }

Q_SIGNALS:
    void availabilityChanged();

protected:
    void ext_background_effect_manager_v1_capabilities(uint32_t flags) override
    {
        const bool supports = flags & EXT_BACKGROUND_EFFECT_MANAGER_V1_CAPABILITY_BLUR;
        if (m_supportsBlur == supports) {
            return;
        }
        m_supportsBlur = supports;
        Q_EMIT availabilityChanged();
    }

private:
    bool m_supportsBlur = false;
};

BackgroundEffectManager *standardManager()
{
    // The extension must be constructed after QGuiApplication. Parenting it
    // to the application also tears the proxy down while the Wayland QPA is
    // still alive.
    static BackgroundEffectManager *manager = new BackgroundEffectManager(qGuiApp);
    return manager;
}

} // namespace

class BackgroundEffectPrivate
{
public:
    explicit BackgroundEffectPrivate(BackgroundEffect *owner)
        : theme(owner)
    {
    }

    PlasmaThemeBlurSetting theme;
    QPointer<QWindow> window;
    QMetaObject::Connection windowDestroyedConnection;
    bool enabled = true;
    bool updateQueued = false;
    bool managerConnected = false;
    bool active = false;
    bool standardProtocol = false;
    bool themeAllows = true;
    bool compositorSupport = false;
};

BackgroundEffect::BackgroundEffect(QObject *parent)
    : QObject(parent)
    , d(std::make_unique<BackgroundEffectPrivate>(this))
{
    d->themeAllows = d->theme.allowsBlur();
    connect(&d->theme, &PlasmaThemeBlurSetting::changed, this, [this]() {
        const bool allowed = d->theme.allowsBlur();
        if (d->themeAllows != allowed) {
            d->themeAllows = allowed;
            Q_EMIT themeAllowsBlurChanged();
        }
        scheduleUpdate();
    });
}

BackgroundEffect::~BackgroundEffect()
{
    detachWindow();
}

QWindow *BackgroundEffect::window() const
{
    return d->window;
}

void BackgroundEffect::setWindow(QWindow *window)
{
    if (d->window == window) {
        return;
    }

    detachWindow();
    d->window = window;

    if (d->window) {
        d->window->installEventFilter(this);
        d->windowDestroyedConnection = connect(d->window, &QObject::destroyed, this, [this]() {
            d->window = nullptr;
            publishState(false, false, false);
            Q_EMIT windowChanged();
        });
    }

    Q_EMIT windowChanged();
    scheduleUpdate();
}

bool BackgroundEffect::isEnabled() const
{
    return d->enabled;
}

void BackgroundEffect::setEnabled(bool enabled)
{
    if (d->enabled == enabled) {
        return;
    }
    d->enabled = enabled;
    Q_EMIT enabledChanged();
    scheduleUpdate();
}

bool BackgroundEffect::isActive() const
{
    return d->active;
}

bool BackgroundEffect::isUsingStandardProtocol() const
{
    return d->standardProtocol;
}

bool BackgroundEffect::themeAllowsBlur() const
{
    return d->themeAllows;
}

bool BackgroundEffect::compositorSupportsBlur() const
{
    return d->compositorSupport;
}

bool BackgroundEffect::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != d->window) {
        return QObject::eventFilter(watched, event);
    }

    if (event->type() == QEvent::PlatformSurface) {
        const auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) {
            publishState(false, false, false);
        } else {
            scheduleUpdate();
        }
    } else if (event->type() == QEvent::Resize || event->type() == QEvent::Show) {
        scheduleUpdate();
    }

    return QObject::eventFilter(watched, event);
}

void BackgroundEffect::scheduleUpdate()
{
    if (d->updateQueued) {
        return;
    }
    d->updateQueued = true;
    QMetaObject::invokeMethod(this, &BackgroundEffect::updateEffect, Qt::QueuedConnection);
}

void BackgroundEffect::updateEffect()
{
    d->updateQueued = false;

    if (!d->window) {
        publishState(false, false, false);
        return;
    }

    const bool wayland = isWaylandPlatform();
    BackgroundEffectManager *manager = nullptr;
    if (wayland) {
        manager = standardManager();
        if (!d->managerConnected) {
            connect(manager,
                &BackgroundEffectManager::availabilityChanged,
                this,
                &BackgroundEffect::scheduleUpdate);
            d->managerConnected = true;
        }
    }

    d->themeAllows = d->theme.allowsBlur();

    if (!wayland) {
        const bool available = KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
        const bool active = d->enabled && d->themeAllows && available;
        KWindowEffects::enableBlurBehind(d->window, active);
        publishState(active, false, active);
        return;
    }

    const bool standardGlobal = manager->isActive();
    const bool standardBlur = manager->supportsBlur();

    if (!d->enabled || !d->themeAllows) {
        // DashboardWindow asks KWindowEffects for blur during its own
        // construction and on every Show. Explicitly remove that request so
        // the widget setting and Plasma theme remain authoritative. On modern
        // KWindowSystem this leaves a null-region ext-background-effect object
        // on the surface, which is what KWindowEffects itself does on disable.
        KWindowEffects::enableBlurBehind(d->window, false);
        publishState(false, standardGlobal, standardGlobal && standardBlur);
        return;
    }

    if (standardGlobal) {
        // KWindowEffects is the single owner of the ext effect object for this
        // surface. Re-requesting through it keeps one object per wl_surface
        // and lets its expose/capability handlers maintain the region.
        KWindowEffects::enableBlurBehind(d->window, true);
        publishState(standardBlur, true, standardBlur);
        return;
    }

    // Plasma/KWin before ext-background-effect-v1 still uses the KDE protocol
    // through KWindowEffects. This path also keeps XWayland-era development
    // sessions functional.
    {
        const bool available = KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
        KWindowEffects::enableBlurBehind(d->window, available);
        publishState(available, false, available);
    }
}

void BackgroundEffect::detachWindow()
{
    if (!d->window) {
        return;
    }

    KWindowEffects::enableBlurBehind(d->window, false);
    d->window->removeEventFilter(this);
    disconnect(d->windowDestroyedConnection);
    d->window = nullptr;
    publishState(false, false, false);
}

void BackgroundEffect::publishState(bool active, bool standardProtocol, bool compositorSupport)
{
    if (d->active != active) {
        d->active = active;
        Q_EMIT activeChanged();
    }
    if (d->standardProtocol != standardProtocol) {
        d->standardProtocol = standardProtocol;
        Q_EMIT backendChanged();
    }
    if (d->compositorSupport != compositorSupport) {
        d->compositorSupport = compositorSupport;
        Q_EMIT compositorSupportsBlurChanged();
    }
}

#include "backgroundeffect.moc"
