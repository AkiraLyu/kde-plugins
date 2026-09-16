// SPDX-License-Identifier: GPL-2.0-or-later
#include "searchindex.h"

#include <QDateTime>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QtQml/qqml.h>
#include <algorithm>
#include <cmath>

namespace {
constexpr int historyLimit = 512;
constexpr int maximumIdLength = 1024;
constexpr qint64 day = 24 * 60 * 60;
constexpr qint64 historyLifetime = 90 * day;
constexpr double frequencyHalfLife = 7 * day;
constexpr double maximumWeight = 32;

double decayedWeight(double weight, qint64 age)
{
    return weight * std::exp2(-double(std::max<qint64>(0, age)) / frequencyHalfLife);
}

QString stringProperty(const QJSValue &value, const QString &key)
{
    const auto property = value.property(key);
    return property.isNull() || property.isUndefined() ? QString() : property.toString();
}
}

SearchIndex::SearchIndex(QObject *parent) : QObject(parent) {}
QJSValue SearchIndex::applications() const { return m_applications; }
int SearchIndex::count() const { return m_results.size(); }
QString SearchIndex::historyData() const { return m_historyData; }
bool SearchIndex::historyEnabled() const { return m_historyEnabled; }
int SearchIndex::historyCount() const { return m_history.size(); }

double SearchIndex::historyScoreFor(const QString &id) const
{
    const int index = m_byId.value(id, -1);
    return index >= 0 ? m_entries[index].historyScore : 0;
}

double SearchIndex::usageScore(const Usage &usage, qint64 now)
{
    const auto age = std::max<qint64>(0, now - usage.lastUsed);
    if (age > historyLifetime) {
        return 0;
    }
    // Saturated, decaying frequency plus a short recency bonus: old habits
    // can be replaced, and one accidental launch cannot dominate relevance.
    return 4 * std::log2(1 + decayedWeight(usage.weight, age))
        + 2 * std::exp2(-double(age) / day);
}

void SearchIndex::trimHistory(qint64 now, const QString &keepId)
{
    m_history.removeIf([now](const auto &item) {
        return now - item.value().lastUsed > historyLifetime;
    });
    if (m_history.size() <= historyLimit) {
        return;
    }
    struct Candidate {
        QString id;
        double score;
        bool keep;
    };
    QVector<Candidate> candidates;
    candidates.reserve(m_history.size());
    for (auto it = m_history.cbegin(); it != m_history.cend(); ++it) {
        candidates.push_back({it.key(), usageScore(it.value(), now), it.key() == keepId});
    }
    // A launch normally adds just one record. Select the retained set in
    // linear time and compute decay once per record, outside the comparator.
    std::nth_element(candidates.begin(), candidates.begin() + historyLimit, candidates.end(),
        [](const Candidate &left, const Candidate &right) {
        if (left.keep != right.keep) {
            return left.keep;
        }
        return left.score == right.score ? left.id < right.id : left.score > right.score;
    });
    for (int row = historyLimit; row < candidates.size(); ++row) {
        m_history.remove(candidates[row].id);
    }
}

void SearchIndex::serializeHistory()
{
    // Only called when history changes, never while matching a keystroke.
    QJsonArray apps;
    auto ids = m_history.keys();
    std::sort(ids.begin(), ids.end());
    for (const auto &id : ids) {
        const auto usage = m_history.value(id);
        apps.append(QJsonObject{{QStringLiteral("id"), id},
            {QStringLiteral("weight"), usage.weight},
            {QStringLiteral("lastUsed"), usage.lastUsed}});
    }
    m_historyData = apps.isEmpty() ? QString() : QString::fromUtf8(QJsonDocument(QJsonObject{
        {QStringLiteral("version"), 1}, {QStringLiteral("apps"), apps}}).toJson(QJsonDocument::Compact));
}

void SearchIndex::setHistoryData(const QString &data)
{
    if (data == m_historyData) {
        return;
    }
    m_history.clear();
    const auto now = QDateTime::currentSecsSinceEpoch();
    // Bound imported configuration too. Unknown IDs are kept until expiry so
    // a temporarily empty model or a hidden application does not erase memory.
    const auto document = data.size() <= 1024 * 1024
        ? QJsonDocument::fromJson(data.toUtf8()) : QJsonDocument();
    const auto object = document.object();
    if (object.value(QStringLiteral("version")).toInt() == 1) {
        const auto apps = object.value(QStringLiteral("apps")).toArray();
        for (const auto &value : apps) {
            const auto item = value.toObject();
            const auto id = item.value(QStringLiteral("id")).toString();
            const auto weight = item.value(QStringLiteral("weight")).toDouble();
            const auto timestamp = item.value(QStringLiteral("lastUsed")).toDouble();
            if (id.isEmpty() || id.size() > maximumIdLength || !std::isfinite(weight) || weight <= 0
                || !std::isfinite(timestamp) || timestamp <= 0 || timestamp > double(now + day)
                || timestamp < double(now - historyLifetime)) {
                continue;
            }
            const Usage usage{std::min(weight, maximumWeight), std::min(qint64(timestamp), now)};
            const auto previous = m_history.constFind(id);
            if (previous == m_history.cend() || usage.lastUsed > previous->lastUsed
                || (usage.lastUsed == previous->lastUsed && usage.weight > previous->weight)) {
                m_history.insert(id, usage);
            }
        }
    }
    trimHistory(now);
    serializeHistory();
    m_historyScoresDirty = true;
    m_dirty = true;
    Q_EMIT historyChanged();
}

void SearchIndex::setHistoryEnabled(bool enabled)
{
    if (enabled == m_historyEnabled) {
        return;
    }
    m_historyEnabled = enabled;
    m_historyScoresDirty = true;
    m_dirty = true;
    Q_EMIT historyEnabledChanged();
}

bool SearchIndex::recordLaunch(const QString &id)
{
    if (!m_historyEnabled || id.size() > maximumIdLength || !m_byId.contains(id)) {
        return false;
    }
    const auto now = QDateTime::currentSecsSinceEpoch();
    const auto previous = m_history.value(id, Usage{0, now});
    m_history.insert(id, {std::min(maximumWeight,
        decayedWeight(previous.weight, now - previous.lastUsed) + 1), now});
    trimHistory(now, id);
    serializeHistory();
    m_historyScoresDirty = true;
    // Keep the active query's order stable, including late KRunner updates.
    // A new query (or reopening search) takes the next history snapshot.
    Q_EMIT historyChanged();
    return true;
}

void SearchIndex::refreshHistoryScores(qint64 now)
{
    if (!m_historyScoresDirty && now >= m_historyScoredAt && now - m_historyScoredAt < 60) {
        return;
    }
    for (auto &entry : m_entries) {
        entry.historyScore = 0;
    }
    if (m_historyEnabled) {
        for (auto it = m_history.cbegin(); it != m_history.cend(); ++it) {
            const auto entry = m_byId.constFind(it.key());
            if (entry != m_byId.cend()) {
                m_entries[*entry].historyScore = usageScore(it.value(), now);
            }
        }
    }
    m_historyScoresDirty = false;
    m_historyScoredAt = now;
}

QString SearchIndex::normalize(const QString &text)
{
    auto result = QLocale().toLower(text).normalized(QString::NormalizationForm_D);
    result.removeIf([](QChar character) {
        return character.unicode() >= 0x0300 && character.unicode() <= 0x036f;
    });
    return result;
}

void SearchIndex::setApplications(const QJSValue &applications)
{
    if (m_applications.strictlyEquals(applications)) {
        return;
    }
    m_applications = applications;
    m_entries.clear();
    m_byId.clear();
    const int length = applications.isArray() ? applications.property(QStringLiteral("length")).toInt() : 0;
    m_entries.reserve(length);
    m_byId.reserve(length);
    for (int row = 0; row < length; ++row) {
        const auto app = applications.property(row);
        const auto id = stringProperty(app, QStringLiteral("id"));
        if (id.isEmpty() || m_byId.contains(id)) {
            continue;
        }
        m_byId.insert(id, m_entries.size());
        m_entries.push_back({app, QJSValue(),
            normalize(stringProperty(app, QStringLiteral("title"))),
            normalize(stringProperty(app, QStringLiteral("description"))), normalize(id)});
    }
    // The controller publishes a complete local/provider snapshot after search().
    m_dirty = true;
    m_historyScoresDirty = true;
    Q_EMIT applicationsChanged();
}

int SearchIndex::score(const Entry &entry, const QStringList &tokens, bool descriptions)
{
    int result = 0;
    for (const auto &token : tokens) {
        if (entry.title == token) {
            continue;
        }
        if (entry.title.startsWith(token)) {
            result += 10;
        } else if (entry.title.contains(QLatin1Char(' ') + token)) {
            result += 20;
        } else if (entry.title.contains(token)) {
            result += 30;
        } else if (descriptions && entry.description.contains(token)) {
            result += 60;
        } else if (entry.id.contains(token)) {
            result += 80;
        } else {
            return -1;
        }
    }
    return result * 1000 + std::min<qsizetype>(entry.title.size(), 100);
}

bool SearchIndex::search(const QString &query, bool includeDescriptions)
{
    const auto normalized = normalize(query).simplified();
    if (!m_dirty && normalized == m_query && includeDescriptions == m_descriptions) {
        return false;
    }
    m_query = normalized;
    m_descriptions = includeDescriptions;
    m_scratch.clear();
    m_scratch.reserve(m_entries.size());
    if (!normalized.isEmpty()) {
        refreshHistoryScores(QDateTime::currentSecsSinceEpoch());
        const auto tokens = normalized.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        for (int index = 0; index < m_entries.size(); ++index) {
            const int rank = score(m_entries[index], tokens, includeDescriptions);
            if (rank >= 0) {
                m_scratch.push_back({index, rank, m_entries[index].historyScore});
            }
        }
        std::sort(m_scratch.begin(), m_scratch.end(), [](const Match &left, const Match &right) {
            // Text match quality remains authoritative. Memory only breaks
            // ties within a match tier, before title length and source order.
            if (left.score / 1000 != right.score / 1000) {
                return left.score < right.score;
            }
            if (left.historyScore != right.historyScore) {
                return left.historyScore > right.historyScore;
            }
            return left.score == right.score ? left.index < right.index : left.score < right.score;
        });
    }
    bool changed = m_dirty || m_results.size() != m_scratch.size();
    if (!changed) {
        for (int row = 0; row < m_results.size(); ++row) {
            if (m_results[row] != m_scratch[row].index) {
                changed = true;
                break;
            }
        }
    }
    m_dirty = false;
    if (!changed) {
        return false;
    }
    m_results.resize(m_scratch.size());
    m_matched.fill(false, m_entries.size());
    for (int row = 0; row < m_scratch.size(); ++row) {
        m_results[row] = m_scratch[row].index;
        m_matched.setBit(m_results[row]);
    }
    Q_EMIT resultsChanged();
    return true;
}

QJSValue SearchIndex::materialize(int index)
{
    if (index < 0 || index >= m_entries.size()) {
        return QJSValue(QJSValue::NullValue);
    }
    auto &entry = m_entries[index];
    if (entry.cached.isUndefined()) {
        auto *engine = qjsEngine(this);
        if (!engine) {
            return QJSValue(QJSValue::NullValue);
        }
        auto object = engine->newObject();
        object.setProperty(QStringLiteral("type"), QStringLiteral("app"));
        for (const auto *key : {"id", "title", "description", "url"}) {
            object.setProperty(QString::fromLatin1(key), stringProperty(entry.source, QString::fromLatin1(key)));
        }
        const auto icon = entry.source.property(QStringLiteral("icon"));
        object.setProperty(QStringLiteral("icon"), icon.isNull() || icon.isUndefined()
            ? QJSValue(QStringLiteral("application-x-executable")) : icon);
        const auto sourceRow = entry.source.property(QStringLiteral("sourceRow"));
        object.setProperty(QStringLiteral("sourceRow"), sourceRow.isNull() || sourceRow.isUndefined()
            ? -1 : sourceRow.toInt());
        object.setProperty(QStringLiteral("apps"), engine->newArray());
        object.setProperty(QStringLiteral("previewIcons"), engine->newArray());
        entry.cached = object;
    }
    return entry.cached;
}

QJSValue SearchIndex::entryAt(int index)
{
    return materialize(index >= 0 && index < m_results.size() ? m_results[index] : -1);
}

QJSValue SearchIndex::application(const QString &id)
{
    return materialize(m_byId.value(id, -1));
}

bool SearchIndex::contains(const QString &id) const
{
    const int index = m_byId.value(id, -1);
    return index >= 0 && index < m_matched.size() && m_matched.testBit(index);
}
