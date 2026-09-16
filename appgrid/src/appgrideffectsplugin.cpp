// SPDX-FileCopyrightText: 2026 AppGrid contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "backgroundeffect.h"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class AppGridEffectsPlugin final : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QLatin1String(uri) == QLatin1String("org.kde.plasma.appgrid.effects"));
        qmlRegisterType<BackgroundEffect>(uri, 1, 0, "BackgroundEffect");
    }
};

#include "appgrideffectsplugin.moc"
