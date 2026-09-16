// SPDX-License-Identifier: GPL-2.0-or-later
#include "pagemodel.h"
#include "searchindex.h"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class AppGridCorePlugin final : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<SearchIndex>(uri, 1, 0, "SearchIndex");
        qmlRegisterType<PageModel>(uri, 1, 0, "PageModel");
    }
};

#include "appgridcoreplugin.moc"
