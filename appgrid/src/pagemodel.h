// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <algorithm>

// Changing a QML integer model resets the view. Incremental row changes keep
// the first page and its warmed icon delegates alive while search counts vary.
class PageModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count WRITE setCount NOTIFY countChanged)
public:
    explicit PageModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int count() const { return m_count; }
    int rowCount(const QModelIndex &parent = QModelIndex()) const override { return parent.isValid() ? 0 : m_count; }
    QVariant data(const QModelIndex &, int) const override { return {}; }
    void setCount(int count)
    {
        count = std::max(1, count);
        if (count == m_count) {
            return;
        }
        if (count > m_count) {
            beginInsertRows({}, m_count, count - 1);
            m_count = count;
            endInsertRows();
        } else {
            beginRemoveRows({}, count, m_count - 1);
            m_count = count;
            endRemoveRows();
        }
        Q_EMIT countChanged();
    }
Q_SIGNALS:
    void countChanged();
private:
    int m_count = 1;
};
