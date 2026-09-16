function readEnvironmentLevel() {
    try {
        if (typeof Services !== "undefined" && Services?.env) {
            const value = Services.env.get("GARP_DEBUG");
            if (value === "2" || value === "trace" || value === "TRACE")
                return 2;
            if (value === "1" || value === "true" || value === "TRUE" || value === "yes" || value === "YES")
                return 1;
        }
    }
    catch (_) {
    }
    return 0;
}

function sanitize(value, depth = 0) {
    if (depth > 4)
        return "[depth-limit]";
    if (value === null || value === undefined)
        return value;
    if (typeof value === "string")
        return value.length > 300 ? `${value.slice(0, 300)}...[${value.length} chars]` : value;
    if (typeof value === "bigint")
        return String(value);
    if (typeof value !== "object")
        return value;
    if (Array.isArray(value))
        return value.slice(0, 40).map(item => sanitize(item, depth + 1));
    const result = {};
    for (const [key, item] of Object.entries(value).slice(0, 60))
        result[key] = sanitize(item, depth + 1);
    return result;
}

export function getGarpDebugLevel(explicitLevel = null) {
    if (explicitLevel !== null && explicitLevel !== undefined) {
        const n = Number(explicitLevel);
        if (Number.isFinite(n))
            return Math.max(0, Math.min(2, Math.trunc(n)));
    }
    return readEnvironmentLevel();
}

export function garpDebug(level, message, details = {}, explicitLevel = null) {
    if (getGarpDebugLevel(explicitLevel) < level)
        return;
    let suffix = "";
    try {
        const clean = sanitize(details);
        if (clean && typeof clean === "object" && Object.keys(clean).length)
            suffix = ` ${JSON.stringify(clean)}`;
    }
    catch (_) {
        suffix = " {details_unserializable:true}";
    }
    dump(`GARP/1.24 DEBUG ${new Date().toISOString()} [L${level}] ${message}${suffix}\n`);
}

export function garpError(message, details = {}) {
    let suffix = "";
    try {
        suffix = ` ${JSON.stringify(sanitize(details))}`;
    }
    catch (_) {
        suffix = " {details_unserializable:true}";
    }
    dump(`GARP/1.24 ERROR ${new Date().toISOString()} ${message}${suffix}\n`);
}
