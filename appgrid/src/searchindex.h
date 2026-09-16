// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QBitArray>
#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QStringList>
#include <QVector>

// Keep ranking and result storage out of the QML heap. Only entries requested
// by visible slots become JS objects; those objects survive query refinement.
class SearchIndex : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QJSValue applications READ applications WRITE setApplications NOTIFY applicationsChanged)
    Q_PROPERTY(int count READ count NOTIFY resultsChanged)
    Q_PROPERTY(QString historyData READ historyData WRITE setHistoryData NOTIFY historyChanged)
    Q_PROPERTY(bool historyEnabled READ historyEnabled WRITE setHistoryEnabled NOTIFY historyEnabledChanged)
    Q_PROPERTY(int historyCount READ historyCount NOTIFY historyChanged)

public:
    explicit SearchIndex(QObject *parent = nullptr);
    QJSValue applications() const;
    void setApplications(const QJSValue &applications);
    int count() const;
    QString historyData() const;
    void setHistoryData(const QString &data);
    bool historyEnabled() const;
    void setHistoryEnabled(bool enabled);
    int historyCount() const;
    Q_INVOKABLE bool recordLaunch(const QString &id);
    Q_INVOKABLE double historyScoreFor(const QString &id) const;
    Q_INVOKABLE bool search(const QString &query, bool includeDescriptions = true);
    Q_INVOKABLE QJSValue entryAt(int index);
    Q_INVOKABLE QJSValue application(const QString &id);
    Q_INVOKABLE bool contains(const QString &id) const;

Q_SIGNALS:
    void applicationsChanged();
    void resultsChanged();
    void historyChanged();
    void historyEnabledChanged();

private:
    struct Entry {
        QJSValue source;
        QJSValue cached;
        QString title;
        QString description;
        QString id;
        double historyScore = 0;
    };
    struct Match {
        int index;
        int score;
        double historyScore;
    };
    struct Usage {
        double weight;
        qint64 lastUsed;
    };
    QJSValue materialize(int index);
    static QString normalize(const QString &text);
    static int score(const Entry &entry, const QStringList &tokens, bool descriptions);
    static double usageScore(const Usage &usage, qint64 now);
    void trimHistory(qint64 now, const QString &keepId = {});
    void serializeHistory();
    void refreshHistoryScores(qint64 now);

    QJSValue m_applications;
    QVector<Entry> m_entries;
    QHash<QString, int> m_byId;
    QVector<int> m_results;
    QVector<Match> m_scratch;
    QBitArray m_matched;
    QString m_query;
    bool m_descriptions = true;
    bool m_dirty = true;
    QHash<QString, Usage> m_history;
    QString m_historyData;
    qint64 m_historyScoredAt = 0;
    bool m_historyEnabled = true;
    bool m_historyScoresDirty = true;
};
