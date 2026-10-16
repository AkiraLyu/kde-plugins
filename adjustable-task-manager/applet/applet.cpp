// SPDX-License-Identifier: GPL-2.0-or-later

#include <KLocalizedString>
#include <KPluginFactory>
#include <Plasma/Applet>

class AdjustableTaskManagerApplet : public Plasma::Applet
{
    Q_OBJECT

public:
    AdjustableTaskManagerApplet(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
        : Plasma::Applet(parent, data, args)
    {
        // Register the stock QML backend before our QML is loaded. Sharing it also
        // shares shortcut dispatch and launcher badges with other task managers.
        const auto backend = KPluginMetaData::findPluginById(QStringLiteral("plasma/applets"), QStringLiteral("org.kde.plasma.taskmanager"));
        const auto result = KPluginFactory::loadFactory(backend);
        if (!result) {
            setLaunchErrorMessage(i18n("The Plasma Task Manager backend could not be loaded: %1", result.errorString));
        }
    }
};

K_PLUGIN_CLASS_WITH_JSON(AdjustableTaskManagerApplet, "metadata.json")

#include "applet.moc"
