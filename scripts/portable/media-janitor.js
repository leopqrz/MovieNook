"use strict";

// MovieNook media janitor.
//
// Delete a movie or show the normal way (Plex's own Delete, or the Trash in Finder/Explorer)
// and this service removes what is left behind: the Radarr/Sonarr entry, which would otherwise
// download the title again, and the Seerr record, so the title can be requested again later.
//
// It never deletes a media file that still exists. It only reacts to files that are already gone:
//   1. A file Radarr/Sonarr still lists is missing from disk on several checks in a row
//      -> ask Radarr/Sonarr to rescan that title (non-destructive).
//   2. Radarr/Sonarr itself then records the file as "MissingFromDisk" and the title has no
//      files left, no newer download and nothing queued -> remove the title everywhere.
// Deletions recorded before this service first ran are left alone.
//
// It also keeps the owner's Plex Watchlist and the downloads in step, because the Watchlist is
// how titles are requested from inside Plex:
//   - A title deleted as above is taken off the Watchlist, otherwise it would be requested again.
//   - A title taken off the Watchlist before it finished downloading is cancelled everywhere.
//     A title that already has files is kept: delete it in Plex to remove it.

const fs = require("fs");
const path = require("path");

const env = process.env;
const configDir = env.MOVIENOOK_CONFIG_DIR || "/movienook/config";
const stateFile = env.MOVIENOOK_JANITOR_STATE || "/state/state.json";
const intervalMs = Math.max(10, Number(env.MOVIENOOK_JANITOR_INTERVAL_SECONDS) || 60) * 1000;
const requiredStrikes = Math.max(2, Number(env.MOVIENOOK_JANITOR_CONFIRMATIONS) || 3);
const dryRun = env.MOVIENOOK_JANITOR_DRY_RUN === "1";
const runOnce = process.argv.includes("--once");
const mediaRoots = ["/data/media/Movies", "/data/media/TV"];
const base = {
  plex: "http://plex:32400",
  radarr: "http://radarr:7878",
  sonarr: "http://sonarr:8989",
  seerr: "http://seerr:5055/api/v1"
};

const discover = "https://discover.provider.plex.tv";

const strikes = new Map();
let baseline = null;

function log(message) {
  console.log(`${new Date().toISOString()} ${dryRun ? "[dry-run] " : ""}${message}`);
}

function readKeys() {
  const xmlKey = file => (fs.readFileSync(file, "utf8").match(/<ApiKey>([^<]+)<\/ApiKey>/) || [])[1];
  const plexPreferences = path.join(configDir, "plex/Library/Application Support/Plex Media Server/Preferences.xml");
  return {
    radarr: xmlKey(path.join(configDir, "radarr/config.xml")),
    sonarr: xmlKey(path.join(configDir, "sonarr/config.xml")),
    seerr: JSON.parse(fs.readFileSync(path.join(configDir, "seerr/settings.json"), "utf8")).main?.apiKey,
    plex: (fs.readFileSync(plexPreferences, "utf8").match(/PlexOnlineToken="([^"]+)"/) || [])[1]
  };
}

function loadBaseline() {
  try {
    const saved = JSON.parse(fs.readFileSync(stateFile, "utf8")).baseline;
    if (saved && !Number.isNaN(Date.parse(saved))) return new Date(saved);
  } catch {
    // First run, or the state folder is not writable; fall through.
  }
  const now = new Date();
  try {
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    fs.writeFileSync(stateFile, `${JSON.stringify({ baseline: now.toISOString() }, null, 2)}\n`);
  } catch (error) {
    log(`Could not save state (${error.message}); deletions made while this service is stopped will be ignored.`);
  }
  return now;
}

async function request(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(30000) });
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`${options.method || "GET"} ${new URL(url).pathname} returned ${response.status}`);
    error.status = response.status;
    throw error;
  }
  if (!text) return null;
  return /^[\[{]/.test(text.trim()) ? JSON.parse(text) : text;
}

function api(service, key) {
  const headers = { "Content-Type": "application/json", "X-Api-Key": key };
  return {
    get: route => request(`${base[service]}${route}`, { headers }),
    send: (method, route, body) => request(`${base[service]}${route}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body)
    })
  };
}

// Counts consecutive checks in which a title's files were missing; true once it is confirmed.
function confirmMissing(key, missing) {
  if (!missing) {
    strikes.delete(key);
    return false;
  }
  const count = (strikes.get(key) || 0) + 1;
  strikes.set(key, count);
  return count >= requiredStrikes;
}

function mediaRootsAvailable() {
  return mediaRoots.every(root => {
    try {
      return fs.statSync(root).isDirectory();
    } catch {
      return false;
    }
  });
}

// True when the title's newest "file deleted" event says the file vanished from disk (not an
// upgrade or a delete made inside Radarr/Sonarr), after the baseline, with no download since.
function deletedOutsideManager(history, deletedType) {
  const events = [...history].sort((a, b) => Date.parse(b.date) - Date.parse(a.date));
  const deleted = events.find(event => event.eventType === deletedType);
  if (!deleted || deleted.data?.reason !== "MissingFromDisk") return false;
  if (Date.parse(deleted.date) < baseline.getTime()) return false;
  const newer = events.filter(event => Date.parse(event.date) > Date.parse(deleted.date));
  return !newer.some(event => /grabbed|imported/i.test(event.eventType));
}

function plexHeaders(plexToken) {
  return { "X-Plex-Token": plexToken, Accept: "application/json", "X-Plex-Client-Identifier": "movienook-janitor" };
}

// The owner's Plex Watchlist as a map of "movie:<tmdbId>" / "tv:<tmdbId>" -> Plex rating key.
// Throws when it cannot be read, so a failed request is never mistaken for an empty watchlist.
async function fetchWatchlist(plexToken) {
  const titles = new Map();
  const pageSize = 100;
  for (let start = 0; ; start += pageSize) {
    const page = await request(
      `${discover}/library/sections/watchlist/all?includeGuids=1&X-Plex-Container-Start=${start}&X-Plex-Container-Size=${pageSize}`,
      { headers: plexHeaders(plexToken) }
    );
    const container = page?.MediaContainer;
    if (!container) throw new Error("the Plex Watchlist response was not understood");
    const items = container.Metadata || [];
    for (const item of items) {
      const tmdb = (item.Guid || []).map(guid => /^tmdb:\/\/(\d+)$/.exec(guid.id)).find(Boolean);
      if (tmdb) titles.set(`${item.type === "show" ? "tv" : "movie"}:${tmdb[1]}`, item.ratingKey);
    }
    if (!items.length || start + items.length >= (container.totalSize ?? 0)) break;
  }
  return titles;
}

// A deleted title that stays on the Watchlist would be requested and downloaded again.
async function removeFromWatchlist(context, mediaType, tmdbId, title) {
  if (!context.keys.plex || !tmdbId) return;
  try {
    const watchlist = await context.watchlist();
    const ratingKey = watchlist.get(`${mediaType}:${tmdbId}`);
    if (!ratingKey) return;
    if (!dryRun) {
      await request(`${discover}/actions/removeFromWatchlist?ratingKey=${encodeURIComponent(ratingKey)}`, {
        method: "PUT", headers: plexHeaders(context.keys.plex)
      });
    }
    watchlist.delete(`${mediaType}:${tmdbId}`);
    log(`Took "${title}" off the Plex Watchlist so it is not requested again.`);
  } catch (error) {
    log(`Could not take "${title}" off the Plex Watchlist (${error.message}); it may be requested again.`);
  }
}

async function clearSeerr(seerr, mediaType, tmdbId, title) {
  if (!tmdbId) return;
  let details;
  try {
    details = await seerr.get(`/${mediaType}/${tmdbId}`);
  } catch (error) {
    log(`Seerr lookup for "${title}" failed: ${error.message}`);
    return;
  }
  const mediaId = details?.mediaInfo?.id;
  if (!mediaId) return;
  if (!dryRun) await seerr.send("DELETE", `/media/${mediaId}`);
  log(`Cleared "${title}" from Seerr so it can be requested again.`);
}

async function refreshPlex(plexToken) {
  if (dryRun || !plexToken) return;
  try {
    await request(`${base.plex}/library/sections/all/refresh`, { headers: { "X-Plex-Token": plexToken } });
  } catch (error) {
    log(`Plex refresh failed: ${error.message}`);
  }
}

async function sweepMovies(context) {
  const { keys } = context;
  const radarr = api("radarr", keys.radarr);
  const seerr = api("seerr", keys.seerr);
  const movies = await radarr.get("/api/v3/movie");

  const withFile = movies.filter(movie => movie.hasFile && movie.movieFile?.path);
  const missing = withFile.filter(movie => !fs.existsSync(movie.movieFile.path));
  const everythingGone = withFile.length >= 3 && missing.length === withFile.length;
  if (everythingGone) log("Every movie file looks missing at once; assuming the media folder is unavailable and doing nothing.");
  for (const movie of withFile) {
    const confirmed = confirmMissing(`movie:${movie.id}`, !everythingGone && missing.includes(movie));
    if (!confirmed) continue;
    strikes.delete(`movie:${movie.id}`);
    log(`"${movie.title}" is missing from disk; asking Radarr to rescan it.`);
    if (!dryRun) await radarr.send("POST", "/api/v3/command", { name: "RescanMovie", movieId: movie.id });
  }

  const withoutFile = movies.filter(movie => !movie.hasFile);
  if (!withoutFile.length) return 0;
  const queue = await radarr.get("/api/v3/queue?pageSize=500");
  const queued = new Set((queue.records || []).map(record => record.movieId));
  let removed = 0;
  for (const movie of withoutFile) {
    if (queued.has(movie.id)) continue;
    const history = await radarr.get(`/api/v3/history/movie?movieId=${movie.id}`);
    if (!deletedOutsideManager(history, "movieFileDeleted")) continue;
    if (!dryRun) await radarr.send("DELETE", `/api/v3/movie/${movie.id}?deleteFiles=true&addImportExclusion=false`);
    log(`Removed "${movie.title}" from Radarr because its file was deleted.`);
    await clearSeerr(seerr, "movie", movie.tmdbId, movie.title);
    await removeFromWatchlist(context, "movie", movie.tmdbId, movie.title);
    removed += 1;
  }
  return removed;
}

async function sweepShows(context) {
  const { keys } = context;
  const sonarr = api("sonarr", keys.sonarr);
  const seerr = api("seerr", keys.seerr);
  const shows = await sonarr.get("/api/v3/series");

  const checks = [];
  for (const show of shows.filter(candidate => candidate.statistics?.episodeFileCount > 0)) {
    const files = await sonarr.get(`/api/v3/episodefile?seriesId=${show.id}`);
    checks.push({ show, total: files.length, missing: files.filter(file => !fs.existsSync(file.path)).length });
  }
  const totalFiles = checks.reduce((sum, check) => sum + check.total, 0);
  const totalMissing = checks.reduce((sum, check) => sum + check.missing, 0);
  const everythingGone = totalFiles >= 3 && totalMissing === totalFiles;
  if (everythingGone) log("Every episode file looks missing at once; assuming the media folder is unavailable and doing nothing.");
  for (const { show, missing } of checks) {
    const confirmed = confirmMissing(`show:${show.id}`, !everythingGone && missing > 0);
    if (!confirmed) continue;
    strikes.delete(`show:${show.id}`);
    log(`"${show.title}" has ${missing} episode file(s) missing from disk; asking Sonarr to rescan it.`);
    if (!dryRun) await sonarr.send("POST", "/api/v3/command", { name: "RescanSeries", seriesId: show.id });
  }

  // A show is removed only when every episode file is gone; single deleted episodes are just
  // unmonitored by Sonarr ("Unmonitor Deleted Episodes") so they are not downloaded again.
  const empty = shows.filter(show => !(show.statistics?.episodeFileCount > 0));
  if (!empty.length) return 0;
  const queue = await sonarr.get("/api/v3/queue?pageSize=500");
  const queued = new Set((queue.records || []).map(record => record.seriesId));
  let removed = 0;
  for (const show of empty) {
    if (queued.has(show.id)) continue;
    const history = await sonarr.get(`/api/v3/history/series?seriesId=${show.id}`);
    if (!deletedOutsideManager(history, "episodeFileDeleted")) continue;
    if (!dryRun) await sonarr.send("DELETE", `/api/v3/series/${show.id}?deleteFiles=true&addImportListExclusion=false`);
    log(`Removed "${show.title}" from Sonarr because all of its episodes were deleted.`);
    await clearSeerr(seerr, "tv", show.tmdbId, show.title);
    await removeFromWatchlist(context, "tv", show.tmdbId, show.title);
    removed += 1;
  }
  return removed;
}

// Removes a not-yet-downloaded title and anything queued for it. Returns its title, or null
// when the title already has files and must be kept.
async function cancelDownload(service, key, mediaType, tmdbId) {
  const manager = api(service, key);
  const collection = mediaType === "movie" ? "movie" : "series";
  const idField = mediaType === "movie" ? "movieId" : "seriesId";
  const entry = (await manager.get(`/api/v3/${collection}`)).find(candidate => candidate.tmdbId === tmdbId);
  if (!entry) return `TMDB ${tmdbId}`;
  const hasFiles = mediaType === "movie" ? entry.hasFile : entry.statistics?.episodeFileCount > 0;
  if (hasFiles) return null;
  const queue = await manager.get("/api/v3/queue?pageSize=500");
  for (const record of (queue.records || []).filter(candidate => candidate[idField] === entry.id)) {
    if (!dryRun) await manager.send("DELETE", `/api/v3/queue/${record.id}?removeFromClient=true&blocklist=false`);
  }
  const exclusion = mediaType === "movie" ? "addImportExclusion" : "addImportListExclusion";
  if (!dryRun) await manager.send("DELETE", `/api/v3/${collection}/${entry.id}?deleteFiles=true&${exclusion}=false`);
  return entry.title;
}

// Titles are requested by putting them on the Plex Watchlist, so taking one off again before it
// has finished downloading cancels it. Only requests Seerr made from the Watchlist are considered.
async function sweepWatchlist(context) {
  const { keys } = context;
  if (!keys.plex) return 0;
  const seerr = api("seerr", keys.seerr);
  const requests = [];
  for (let skip = 0; ; skip += 100) {
    const page = await seerr.get(`/request?take=100&skip=${skip}&filter=all&sort=added`);
    const results = page.results || [];
    requests.push(...results);
    if (!results.length || requests.length >= (page.pageInfo?.results ?? 0)) break;
  }
  // Request status 1 = pending, 2 = approved. Media status 4 = partially available, 5 = available.
  const pending = new Map();
  for (const item of requests) {
    if (!item.isAutoRequest || !item.media?.tmdbId) continue;
    if (![1, 2].includes(item.status) || [4, 5].includes(item.media.status)) continue;
    const mediaType = item.type === "tv" ? "tv" : "movie";
    pending.set(`${mediaType}:${item.media.tmdbId}`, { mediaType, tmdbId: item.media.tmdbId, mediaId: item.media.id });
  }
  for (const key of [...strikes.keys()]) {
    if (key.startsWith("watchlist:") && !pending.has(key.slice("watchlist:".length))) strikes.delete(key);
  }
  if (!pending.size) return 0;

  const watchlist = await context.watchlist();
  let removed = 0;
  for (const [key, item] of pending) {
    if (!confirmMissing(`watchlist:${key}`, !watchlist.has(key))) continue;
    strikes.delete(`watchlist:${key}`);
    const title = item.mediaType === "movie"
      ? await cancelDownload("radarr", keys.radarr, "movie", item.tmdbId)
      : await cancelDownload("sonarr", keys.sonarr, "tv", item.tmdbId);
    if (title === null) continue;
    if (!dryRun) await seerr.send("DELETE", `/media/${item.mediaId}`);
    log(`Cancelled "${title}" because it was taken off the Plex Watchlist before it finished downloading.`);
    removed += 1;
  }
  return removed;
}

async function sweep() {
  if (!mediaRootsAvailable()) {
    log("The media folders are not available; doing nothing.");
    return;
  }
  const keys = readKeys();
  if (!keys.radarr || !keys.sonarr || !keys.seerr) {
    log("Waiting for MovieNook services to create their API keys.");
    return;
  }
  let watchlist = null;
  const context = {
    keys,
    // Read at most once per check, and only when something needs it.
    watchlist: () => (watchlist ??= fetchWatchlist(keys.plex))
  };
  let removed = 0;
  for (const task of [sweepMovies, sweepShows, sweepWatchlist]) {
    try {
      removed += await task(context);
    } catch (error) {
      log(`${task.name} could not finish: ${error.message}`);
    }
  }
  if (removed) await refreshPlex(keys.plex);
}

async function main() {
  baseline = loadBaseline();
  log(`Media janitor started; cleaning up after deletions made since ${baseline.toISOString()}.`);
  for (;;) {
    try {
      await sweep();
    } catch (error) {
      log(`Check failed: ${error.message}`);
    }
    if (runOnce) return;
    await new Promise(resolve => setTimeout(resolve, intervalMs));
  }
}

main();
