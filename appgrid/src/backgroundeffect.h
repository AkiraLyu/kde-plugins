// SPDX-FileCopyrightText: 2026 AppGrid contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QObject>
#include <QPointer>
#include <QWindow>

#include <memory>

class BackgroundEffectPrivate;

/**
 * Requests compositor-side blur for one top-level window.
 *
 * The request itself is always issued through KWindowEffects, because Plasma's
 * KWayland plugin already maps blur to ext-background-effect-v1 on KWin 6.7 and
 * owns the one effect object per wl_surface. This class only observes the
 * standard global to report the backend and to track KWin's live Blur-effect
 * capability. Creating a second ext effect object on the same surface would be
 * a protocol error.
 *
 * The Plasma desktop-theme flag and compositor capability event remain
 * authoritative: disabling blur in either the theme or KWin Desktop Effects
 * removes the request immediately.
 */
class BackgroundEffect : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(bool usingStandardProtocol READ isUsingStandardProtocol NOTIFY backendChanged)
    Q_PROPERTY(bool themeAllowsBlur READ themeAllowsBlur NOTIFY themeAllowsBlurChanged)
    Q_PROPERTY(bool compositorSupportsBlur READ compositorSupportsBlur NOTIFY compositorSupportsBlurChanged)

public:
    explicit BackgroundEffect(QObject *parent = nullptr);
    ~BackgroundEffect() override;

    QWindow *window() const;
    void setWindow(QWindow *window);

    bool isEnabled() const;
    void setEnabled(bool enabled);

    bool isActive() const;
    bool isUsingStandardProtocol() const;
    bool themeAllowsBlur() const;
    bool compositorSupportsBlur() const;

Q_SIGNALS:
    void windowChanged();
    void enabledChanged();
    void activeChanged();
    void backendChanged();
    void themeAllowsBlurChanged();
    void compositorSupportsBlurChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private Q_SLOTS:
    void scheduleUpdate();
    void updateEffect();

private:
    void detachWindow();
    void publishState(bool active, bool standardProtocol, bool compositorSupport);

    std::unique_ptr<BackgroundEffectPrivate> d;
};
