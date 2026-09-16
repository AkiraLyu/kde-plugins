.pragma library

const CURRENT_VERSION = 1;

function _safeString(value) {
    return value === undefined || value === null ? "" : String(value);
}

function _normalizeText(value) {
    let text = _safeString(value).toLocaleLowerCase();
    if (text.normalize) {
        text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    return text;
}

function _parse(serialized) {
    if (serialized && typeof serialized === "object") {
        if (Array.isArray(serialized)) {
            return {version: CURRENT_VERSION, items: serialized};
        }
        return serialized;
    }

    if (!_safeString(serialized).trim()) {
        return {version: CURRENT_VERSION, items: []};
    }

    try {
        const parsed = JSON.parse(serialized);
        if (Array.isArray(parsed)) {
            return {version: CURRENT_VERSION, items: parsed};
        }
        if (parsed && typeof parsed === "object") {
            return parsed;
        }
    } catch (error) {
        // A corrupt setting should never prevent the launcher from opening.
    }

    return {version: CURRENT_VERSION, items: []};
}

function _persistentItem(item) {
    if (item.type === "folder") {
        return {
            type: "folder",
            id: _safeString(item.id),
            name: _safeString(item.name || item.title),
            apps: Array.isArray(item.apps) ? item.apps.map(_safeString) : [],
        };
    }

    return {type: "app", id: _safeString(item.id)};
}

function serialize(items) {
    const persistentItems = [];
    for (const item of items || []) {
        if (!item || (item.type !== "app" && item.type !== "folder")) {
            continue;
        }
        persistentItems.push(_persistentItem(item));
    }

    return JSON.stringify({version: CURRENT_VERSION, items: persistentItems});
}

function _hydrateApp(app) {
    return {
        type: "app",
        id: _safeString(app.id),
        title: _safeString(app.title),
        icon: _safeString(app.icon),
        description: _safeString(app.description),
        sourceRow: Number(app.sourceRow),
        url: _safeString(app.url),
    };
}

function reconcile(serialized, applications, defaultFolderName) {
    const parsed = _parse(serialized);
    const storedItems = parsed.version === CURRENT_VERSION && Array.isArray(parsed.items)
        ? parsed.items
        : [];
    const fallbackFolderName = _safeString(defaultFolderName) || "Unnamed Folder";

    const appById = Object.create(null);
    const installed = [];
    for (const candidate of applications || []) {
        if (!candidate) {
            continue;
        }
        const id = _safeString(candidate.id);
        if (!id || appById[id]) {
            continue;
        }
        const app = _hydrateApp(candidate);
        appById[id] = app;
        installed.push(app);
    }

    const seenApps = Object.create(null);
    const seenFolders = Object.create(null);
    const layout = [];
    let recoveredFolderNumber = 0;

    for (const stored of storedItems) {
        if (!stored || typeof stored !== "object") {
            continue;
        }

        if (stored.type === "folder") {
            const members = [];
            const storedMembers = Array.isArray(stored.apps) ? stored.apps : [];
            for (const rawId of storedMembers) {
                const appId = _safeString(rawId);
                if (!appById[appId] || seenApps[appId]) {
                    continue;
                }
                seenApps[appId] = true;
                members.push(appId);
            }

            if (members.length === 0) {
                continue;
            }

            let folderId = _safeString(stored.id);
            while (!folderId || seenFolders[folderId]) {
                recoveredFolderNumber += 1;
                folderId = `folder-recovered-${recoveredFolderNumber}`;
            }
            seenFolders[folderId] = true;

            const name = _safeString(stored.name).trim() || fallbackFolderName;
            layout.push({
                type: "folder",
                id: folderId,
                name,
                title: name,
                icon: "folder",
                description: "",
                sourceRow: -1,
                url: "",
                apps: members,
            });
            continue;
        }

        if (stored.type === "app") {
            const appId = _safeString(stored.id);
            if (appById[appId] && !seenApps[appId]) {
                seenApps[appId] = true;
                layout.push(_hydrateApp(appById[appId]));
            }
        }
    }

    // KDE's source model is locale-sorted. Keeping that order here makes newly
    // installed applications appear predictably at the end of the user layout.
    for (const app of installed) {
        if (!seenApps[app.id]) {
            seenApps[app.id] = true;
            layout.push(_hydrateApp(app));
        }
    }

    const canonical = serialize(layout);
    const originalCanonical = JSON.stringify({
        version: CURRENT_VERSION,
        items: storedItems
            .filter(item => item && (item.type === "app" || item.type === "folder"))
            .map(_persistentItem),
    });

    return {
        version: CURRENT_VERSION,
        layout,
        changed: parsed.version !== CURRENT_VERSION || canonical !== originalCanonical,
        serialized: canonical,
    };
}

function buildSearchIndex(applications) {
    const index = [];
    let position = 0;
    for (const app of applications || []) {
        index.push({
            app,
            title: _normalizeText(app.title),
            description: _normalizeText(app.description),
            id: _normalizeText(app.id),
            position,
        });
        position += 1;
    }
    return index;
}

function _matchScore(indexedApp, tokens, includeDescriptions) {
    const title = indexedApp.title;
    const description = includeDescriptions ? indexedApp.description : "";
    const id = indexedApp.id;
    const haystack = `${title} ${description} ${id}`;
    let score = 0;

    for (const token of tokens) {
        if (!haystack.includes(token)) {
            return -1;
        }

        if (title === token) {
            score += 0;
        } else if (title.startsWith(token)) {
            score += 10;
        } else if (title.includes(` ${token}`)) {
            score += 20;
        } else if (title.includes(token)) {
            score += 30;
        } else if (description.includes(token)) {
            score += 60;
        } else {
            score += 80;
        }
    }

    return score + Math.min(title.length, 100) / 1000;
}

function searchIndexed(searchIndex, query, includeDescriptions) {
    const normalizedQuery = _normalizeText(query).trim();
    if (!normalizedQuery) {
        return [];
    }

    const tokens = normalizedQuery.split(/\s+/).filter(Boolean);
    const matches = [];
    for (const indexedApp of searchIndex || []) {
        const score = _matchScore(
            indexedApp, tokens, includeDescriptions !== false);
        if (score >= 0) {
            matches.push({
                app: indexedApp.app,
                score,
                position: indexedApp.position,
            });
        }
    }

    matches.sort((left, right) => {
        if (left.score !== right.score) {
            return left.score - right.score;
        }
        return left.position - right.position;
    });

    return matches.map(match => _hydrateApp(match.app));
}

function search(applications, query, includeDescriptions) {
    return searchIndexed(
        buildSearchIndex(applications), query, includeDescriptions);
}
