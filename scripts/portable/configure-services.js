"use strict";

const env = process.env;
const keys = {
  plex: env.MOVIENOOK_PLEX_TOKEN,
  radarr: env.MOVIENOOK_RADARR_KEY,
  sonarr: env.MOVIENOOK_SONARR_KEY,
  prowlarr: env.MOVIENOOK_PROWLARR_KEY,
  seerr: env.MOVIENOOK_SEERR_KEY,
  sabnzbd: env.MOVIENOOK_SABNZBD_KEY
};
const base = {
  plex: "http://plex:32400",
  radarr: "http://radarr:7878",
  sonarr: "http://sonarr:8989",
  prowlarr: "http://prowlarr:9696",
  sabnzbd: "http://sabnzbd:8080",
  seerr: "http://127.0.0.1:5055/api/v1"
};
const paths = {
  movies: "/data/media/Movies",
  television: "/data/media/TV",
  usenetIncomplete: "/data/downloads/usenet/incomplete",
  usenetComplete: "/data/downloads/usenet/complete"
};
const bestProfileName = "Best Available (Auto Upgrade)";

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

async function request(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(20000)
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${options.method || "GET"} ${new URL(url).pathname} returned ${response.status}`);
  }
  if (!text) return null;
  const type = response.headers.get("content-type") || "";
  if (type.includes("json") || /^[\[{]/.test(text.trim())) return JSON.parse(text);
  return text;
}

function apiHeaders(apiKey) {
  return { "Content-Type": "application/json", "X-Api-Key": apiKey };
}

function apiGet(service, path) {
  return request(`${base[service]}${path}`, { headers: apiHeaders(keys[service]) });
}

function apiWrite(service, path, method, body) {
  return request(`${base[service]}${path}`, {
    method,
    headers: apiHeaders(keys[service]),
    body: body === undefined ? undefined : JSON.stringify(body)
  });
}

function setField(schema, name, value) {
  const field = schema.fields.find(candidate => candidate.name === name);
  if (field) field.value = value;
}

function getField(schema, name) {
  return schema.fields?.find(candidate => candidate.name === name)?.value;
}

function normalize(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function configured(value) {
  return Boolean(value && value !== "CHANGE_ME");
}

async function plexRequest(path, options = {}) {
  return request(`${base.plex}${path}`, {
    ...options,
    headers: { ...(options.headers || {}), "X-Plex-Token": keys.plex }
  });
}

async function ensurePlexLibrary(type, name, location, agent, scanner) {
  const sections = await plexRequest("/library/sections");
  if (new RegExp(`type="${type}"`).test(sections)) return;
  const params = new URLSearchParams({ name, type, agent, scanner, language: "en-US", location });
  await plexRequest(`/library/sections?${params}`, { method: "POST" });
  console.log(`Created Plex ${name} library.`);
}

async function ensurePlexReachable() {
  if (!env.MOVIENOOK_PLEX_CUSTOM_CONNECTIONS) return;
  const params = new URLSearchParams({ customConnections: env.MOVIENOOK_PLEX_CUSTOM_CONNECTIONS });
  await plexRequest(`/:/prefs?${params}`, { method: "PUT" });
  console.log("Published the local Plex address so app.plex.tv can reach this server.");
}

async function ensurePlexAutoScan() {
  const params = new URLSearchParams({
    FSEventLibraryUpdatesEnabled: "1",
    FSEventLibraryPartialScanEnabled: "1",
    ScheduledLibraryUpdatesEnabled: "1",
    ScheduledLibraryUpdateInterval: "3600"
  });
  await plexRequest(`/:/prefs?${params}`, { method: "PUT" });
  // Catch up on anything that landed in the media folders while auto-scan was off.
  await plexRequest("/library/sections/all/refresh");
  console.log("Enabled Plex automatic library scans and started a catch-up scan.");
}

async function ensurePlexConnection(service) {
  const schemas = await apiGet(service, "/api/v3/notification/schema");
  const schema = clone(schemas.find(candidate => candidate.implementation === "PlexServer"));
  if (!schema) throw new Error(`${service} has no PlexServer connection schema`);
  schema.name = "MovieNook Plex";
  setField(schema, "host", "plex");
  setField(schema, "port", 32400);
  setField(schema, "useSsl", false);
  setField(schema, "authToken", keys.plex);
  setField(schema, "updateLibrary", true);
  const triggers = [
    "onDownload", "onUpgrade", "onRename", "onImportComplete",
    "onMovieDelete", "onMovieFileDelete", "onMovieFileDeleteForUpgrade",
    "onSeriesDelete", "onEpisodeFileDelete", "onEpisodeFileDeleteForUpgrade"
  ];
  for (const trigger of triggers) {
    if (schema[`supports${trigger.slice(0, 1).toUpperCase()}${trigger.slice(1)}`]) schema[trigger] = true;
  }
  const current = await apiGet(service, "/api/v3/notification");
  const existing = current.find(item => item.implementation === "PlexServer");
  if (existing) {
    schema.id = existing.id;
    await apiWrite(service, `/api/v3/notification/${existing.id}`, "PUT", schema);
  } else {
    delete schema.id;
    await apiWrite(service, "/api/v3/notification", "POST", schema);
  }
}

async function ensureRoot(service, path) {
  const roots = await apiGet(service, "/api/v3/rootfolder");
  const existing = roots.find(root => root.path.replace(/\/$/, "") === path.replace(/\/$/, ""));
  if (existing) return existing;
  const created = await apiWrite(service, "/api/v3/rootfolder", "POST", { path });
  console.log(`Registered the ${service} media folder.`);
  return created;
}

function qualityLeaves(item) {
  return item.items?.length ? item.items.flatMap(qualityLeaves) : (item.quality ? [item] : []);
}

function allowedQualityIds(profile) {
  const ids = new Set();
  for (const item of profile.items || []) {
    for (const leaf of qualityLeaves(item)) {
      if (leaf.allowed && Number(leaf.quality?.resolution) > 0) ids.add(leaf.quality.id);
    }
  }
  return ids;
}

function itemResolution(item) {
  const resolutions = qualityLeaves(item).map(leaf => leaf.quality?.resolution || 0);
  return resolutions.length ? Math.max(...resolutions) : 0;
}

async function ensureBestProfile(service) {
  const profiles = await apiGet(service, "/api/v3/qualityprofile");
  const existing = profiles.find(profile => profile.name === bestProfileName);
  const sourceProfiles = profiles.filter(profile => profile.name !== bestProfileName && profile.name !== "Any");
  const preferred = new Set(sourceProfiles.flatMap(profile => [...allowedQualityIds(profile)]));
  const baseProfile = clone(profiles.find(profile => profile.name === "Any") || profiles[0]);

  if (!preferred.size) {
    for (const item of baseProfile.items || []) {
      for (const leaf of qualityLeaves(item)) {
        if (Number(leaf.quality?.resolution) > 0) preferred.add(leaf.quality.id);
      }
    }
  }

  for (const item of baseProfile.items || []) {
    const leaves = qualityLeaves(item);
    for (const leaf of leaves) leaf.allowed = preferred.has(leaf.quality.id);
    item.allowed = leaves.some(leaf => leaf.allowed);
  }

  const candidates = (baseProfile.items || [])
    .filter(item => item.allowed)
    .map(item => ({ item, resolution: itemResolution(item) }))
    .sort((left, right) => left.resolution - right.resolution);
  const highest = candidates.at(-1);
  if (!highest) throw new Error(`${service} has no enabled video quality to use as an upgrade target`);

  const resolutions = [...new Set(
    candidates.flatMap(({ item }) => qualityLeaves(item)
      .filter(leaf => leaf.allowed)
      .map(leaf => Number(leaf.quality?.resolution))
      .filter(resolution => resolution > 0))
  )].sort((left, right) => left - right);

  baseProfile.name = bestProfileName;
  baseProfile.upgradeAllowed = true;
  baseProfile.cutoff = highest.item.id || highest.item.quality.id;
  if (existing) baseProfile.id = existing.id;
  else delete baseProfile.id;

  const saved = existing
    ? await apiWrite(service, `/api/v3/qualityprofile/${existing.id}`, "PUT", baseProfile)
    : await apiWrite(service, "/api/v3/qualityprofile", "POST", baseProfile);
  console.log(`${service} profile ready: ${resolutions.map(value => `${value}p`).join(" → ")} with upgrades enabled.`);
  return saved;
}

async function migrateMonitoredMedia(service, profileId) {
  const resource = service === "radarr" ? "movie" : "series";
  const items = await apiGet(service, `/api/v3/${resource}`);
  let changed = 0;
  for (const item of items) {
    if (item.monitored !== true || item.qualityProfileId === profileId) continue;
    item.qualityProfileId = profileId;
    await apiWrite(service, `/api/v3/${resource}/${item.id}`, "PUT", item);
    changed += 1;
  }
  if (changed) console.log(`Updated ${changed} monitored ${service} item(s) to Best Available.`);
}

function splitNewznabUrl(raw) {
  const parsed = new URL(raw);
  parsed.hash = "";
  parsed.search = "";
  const match = parsed.pathname.match(/^(.*?)(\/api\/?$)/i);
  if (!match) return { baseUrl: parsed.toString().replace(/\/$/, ""), apiPath: "/api" };
  parsed.pathname = match[1] || "/";
  return { baseUrl: parsed.toString().replace(/\/$/, ""), apiPath: match[2].replace(/\/$/, "") };
}

async function ensureIndexer(record) {
  if (![record.name, record.url, record.apiKey].every(configured)) return false;
  const schemas = await apiGet("prowlarr", "/api/v1/indexer/schema");
  const schema = clone(
    schemas.find(candidate => normalize(candidate.name) === normalize(record.name))
    || schemas.find(candidate => candidate.name === "Generic Newznab")
  );
  if (!schema) throw new Error("Prowlarr has no Newznab-compatible schema");
  const applicationProfiles = await apiGet("prowlarr", "/api/v1/appprofile");
  if (!applicationProfiles.length) throw new Error("Prowlarr has no application profile for an indexer");
  const location = splitNewznabUrl(record.url);
  schema.name = record.name;
  schema.enable = true;
  schema.priority = 25;
  schema.appProfileId = applicationProfiles[0].id;
  setField(schema, "baseUrl", location.baseUrl);
  setField(schema, "apiPath", location.apiPath);
  setField(schema, "apiKey", record.apiKey);

  const current = await apiGet("prowlarr", "/api/v1/indexer");
  const existing = current.find(indexer => normalize(indexer.name) === normalize(record.name));
  if (existing) {
    const existingBaseUrl = String(getField(existing, "baseUrl") || "").replace(/\/$/, "");
    const existingApiPath = String(getField(existing, "apiPath") || "").replace(/\/$/, "");
    const existingApiKey = String(getField(existing, "apiKey") || "");
    const keyIsStoredButMasked = /^\*+$/.test(existingApiKey);
    const connectionMatches =
      existingBaseUrl === location.baseUrl.replace(/\/$/, "") &&
      existingApiPath === location.apiPath.replace(/\/$/, "") &&
      (existingApiKey === record.apiKey || keyIsStoredButMasked);
    if (existing.enable !== false && connectionMatches) {
      console.log("Kept an existing matching Usenet indexer in Prowlarr.");
      return true;
    }
  }
  if (existing) schema.id = existing.id;
  else delete schema.id;
  try {
    if (existing) await apiWrite("prowlarr", `/api/v1/indexer/${existing.id}`, "PUT", schema);
    else await apiWrite("prowlarr", "/api/v1/indexer", "POST", schema);
  } catch (error) {
    if (existing?.enable !== false) {
      console.warn(`Kept an existing Prowlarr indexer because revalidation failed: ${error.message}`);
      return true;
    }
    throw error;
  }
  console.log("Configured one Usenet indexer in Prowlarr.");
  return true;
}

async function ensureProwlarrApplication(implementation, service) {
  const schemas = await apiGet("prowlarr", "/api/v1/applications/schema");
  const schema = clone(schemas.find(candidate => candidate.implementation === implementation));
  if (!schema) throw new Error(`Prowlarr has no ${implementation} application schema`);
  schema.name = `MovieNook ${implementation}`;
  schema.enable = true;
  schema.syncLevel = "fullSync";
  setField(schema, "prowlarrUrl", base.prowlarr);
  setField(schema, "baseUrl", base[service]);
  setField(schema, "apiKey", keys[service]);
  const current = await apiGet("prowlarr", "/api/v1/applications");
  const existing = current.find(application => application.implementation === implementation);
  if (existing) schema.id = existing.id;
  else delete schema.id;
  if (existing) await apiWrite("prowlarr", `/api/v1/applications/${existing.id}`, "PUT", schema);
  else await apiWrite("prowlarr", "/api/v1/applications", "POST", schema);
}

async function sabRequest(parameters) {
  const body = new URLSearchParams({ output: "json", apikey: keys.sabnzbd, ...parameters });
  return request(`${base.sabnzbd}/api`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body
  });
}

async function ensureSabnzbd() {
  const required = [
    keys.sabnzbd,
    env.MOVIENOOK_USENET_PROVIDER_NAME,
    env.MOVIENOOK_USENET_HOST,
    env.MOVIENOOK_USENET_PORT,
    env.MOVIENOOK_USENET_USERNAME,
    env.MOVIENOOK_USENET_PASSWORD
  ];
  if (!required.every(configured)) throw new Error("Usenet provider credentials are incomplete");
  const server = await sabRequest({
    mode: "set_config",
    section: "servers",
    name: env.MOVIENOOK_USENET_PROVIDER_NAME,
    host: env.MOVIENOOK_USENET_HOST,
    port: env.MOVIENOOK_USENET_PORT,
    ssl: /^(1|true|yes)$/i.test(env.MOVIENOOK_USENET_USE_SSL || "") ? "1" : "0",
    username: env.MOVIENOOK_USENET_USERNAME,
    password: env.MOVIENOOK_USENET_PASSWORD,
    enable: "1"
  });
  if (server?.status === false) throw new Error("SABnzbd rejected the Usenet server configuration");

  for (const [keyword, value] of [
    ["download_dir", paths.usenetIncomplete],
    ["complete_dir", paths.usenetComplete]
  ]) {
    const result = await sabRequest({ mode: "set_config", section: "misc", keyword, value });
    if (result?.status === false) throw new Error(`SABnzbd rejected the ${keyword} folder`);
  }
  for (const category of ["movies", "tv"]) {
    const result = await sabRequest({ mode: "set_config", section: "categories", name: category, dir: category });
    if (result?.status === false) throw new Error(`SABnzbd rejected the ${category} category`);
  }
  console.log("Configured the Usenet provider and media categories in SABnzbd.");
}

async function ensureDownloadClient(service, implementation, values) {
  const schemas = await apiGet(service, "/api/v3/downloadclient/schema");
  const schema = clone(schemas.find(candidate => candidate.implementation === implementation));
  if (!schema) throw new Error(`${service} has no ${implementation} download-client schema`);
  schema.name = `MovieNook ${implementation}`;
  schema.enable = true;
  schema.removeCompletedDownloads = true;
  schema.removeFailedDownloads = true;
  for (const [field, value] of Object.entries(values)) setField(schema, field, value);
  const current = await apiGet(service, "/api/v3/downloadclient");
  const existing = current.find(client => client.implementation === implementation);
  if (existing) schema.id = existing.id;
  else delete schema.id;
  if (existing) await apiWrite(service, `/api/v3/downloadclient/${existing.id}`, "PUT", schema);
  else await apiWrite(service, "/api/v3/downloadclient", "POST", schema);
}

async function configureDownloadClients() {
  for (const service of ["radarr", "sonarr"]) {
    const categoryField = service === "radarr" ? "movieCategory" : "tvCategory";
    await ensureDownloadClient(service, "Sabnzbd", {
      host: "sabnzbd",
      port: 8080,
      useSsl: false,
      apiKey: keys.sabnzbd,
      username: env.MOVIENOOK_SABNZBD_USERNAME || "",
      password: env.MOVIENOOK_SABNZBD_PASSWORD || "",
      [categoryField]: service === "radarr" ? "movies" : "tv"
    });
  }
  console.log("Connected Radarr and Sonarr to SABnzbd.");

  if (env.MOVIENOOK_QBITTORRENT_AVAILABLE !== "1") {
    console.log("qBittorrent integration is deferred until its VPN-protected container is running.");
    return;
  }
  for (const service of ["radarr", "sonarr"]) {
    const categoryField = service === "radarr" ? "movieCategory" : "tvCategory";
    await ensureDownloadClient(service, "QBittorrent", {
      host: "qbittorrent",
      port: 8080,
      useSsl: false,
      username: env.MOVIENOOK_QBITTORRENT_USERNAME,
      password: env.MOVIENOOK_QBITTORRENT_PASSWORD,
      [categoryField]: service === "radarr" ? "movies" : "tv"
    });
  }
  console.log("Connected Radarr and Sonarr to qBittorrent.");
}

async function seerrGet(path) {
  return request(`${base.seerr}${path}`, { headers: apiHeaders(keys.seerr) });
}

async function seerrWrite(path, method, body) {
  return request(`${base.seerr}${path}`, {
    method,
    headers: apiHeaders(keys.seerr),
    body: body === undefined ? undefined : JSON.stringify(body)
  });
}

async function upsertSeerrService(kind, body) {
  const current = await seerrGet(`/settings/${kind}`);
  if (current.length) await seerrWrite(`/settings/${kind}/${current[0].id}`, "PUT", body);
  else await seerrWrite(`/settings/${kind}`, "POST", body);
}

async function main() {
  const publicSettings = await request(`${base.seerr}/settings/public`);
  const mainSettings = await seerrGet("/settings/main");
  if (mainSettings.localLogin !== false) {
    await seerrWrite("/settings/main", "POST", { localLogin: false });
    console.log("Configured Seerr for Plex-only sign-in.");
  }

  const identity = await plexRequest("/identity");
  if (!/machineIdentifier="[^"]+"/.test(identity) || !/claimed="1"/.test(identity)) {
    throw new Error("The local Plex server is not claimed yet");
  }
  await seerrWrite("/auth/plex", "POST", { authToken: keys.plex });
  await plexRequest("/:/prefs?FriendlyName=MovieNook", { method: "PUT" });
  await ensurePlexLibrary("movie", "Movies", paths.movies, "tv.plex.agents.movie", "Plex Movie");
  await ensurePlexLibrary("show", "TV Shows", paths.television, "tv.plex.agents.series", "Plex TV Series");
  await ensurePlexReachable();
  await ensurePlexAutoScan();
  await ensurePlexConnection("radarr");
  await ensurePlexConnection("sonarr");
  console.log("Connected Radarr and Sonarr to Plex so finished downloads appear immediately.");
  await seerrWrite("/settings/plex", "POST", {
    ip: "plex", port: 32400, useSsl: false,
    webAppUrl: env.MOVIENOOK_PLEX_WEB_URL || "https://app.plex.tv/desktop"
  });

  await ensureSabnzbd();
  await configureDownloadClients();

  const indexers = [1, 2].map(number => ({
    name: env[`MOVIENOOK_INDEXER_${number}_NAME`],
    url: env[`MOVIENOOK_INDEXER_${number}_URL`],
    apiKey: env[`MOVIENOOK_INDEXER_${number}_API_KEY`]
  }));
  let configuredIndexers = 0;
  for (const indexer of indexers) {
    try {
      if (await ensureIndexer(indexer)) configuredIndexers += 1;
    } catch (error) {
      console.warn(`Skipped one unavailable indexer configuration: ${error.message}`);
    }
  }
  if (!configuredIndexers) throw new Error("No complete indexer credentials were found");
  await ensureProwlarrApplication("Radarr", "radarr");
  await ensureProwlarrApplication("Sonarr", "sonarr");
  await apiWrite("prowlarr", "/api/v1/command", "POST", { name: "ApplicationIndexerSync" });
  console.log(`Prowlarr has ${configuredIndexers} credential-driven indexer configuration(s).`);

  const radarrRoot = await ensureRoot("radarr", paths.movies);
  const sonarrRoot = await ensureRoot("sonarr", paths.television);
  const radarrProfile = await ensureBestProfile("radarr");
  const sonarrProfile = await ensureBestProfile("sonarr");
  await migrateMonitoredMedia("radarr", radarrProfile.id);
  await migrateMonitoredMedia("sonarr", sonarrProfile.id);

  await upsertSeerrService("radarr", {
    name: "MovieNook Radarr", hostname: "radarr", port: 7878, apiKey: keys.radarr,
    useSsl: false, baseUrl: "", activeProfileId: radarrProfile.id,
    activeProfileName: radarrProfile.name, activeDirectory: radarrRoot.path,
    is4k: false, minimumAvailability: "released", isDefault: true,
    externalUrl: "", syncEnabled: true, preventSearch: false
  });
  await upsertSeerrService("sonarr", {
    name: "MovieNook Sonarr", hostname: "sonarr", port: 8989, apiKey: keys.sonarr,
    useSsl: false, baseUrl: "", activeProfileId: sonarrProfile.id,
    activeProfileName: sonarrProfile.name, activeDirectory: sonarrRoot.path,
    is4k: false, enableSeasonFolders: true, isDefault: true,
    externalUrl: "", syncEnabled: true, preventSearch: false
  });

  const libraries = await seerrGet("/settings/plex/library?sync=true");
  const ids = libraries.map(library => library.id).join(",");
  if (ids) await seerrGet(`/settings/plex/library?enable=${encodeURIComponent(ids)}`);
  await seerrWrite("/settings/initialize", "POST");
  console.log(publicSettings.initialized
    ? "MovieNook smart download configuration is ready."
    : "MovieNook first-time smart download configuration completed.");
}

main().catch(error => {
  console.error(`MovieNook configuration failed: ${error.message}`);
  process.exit(1);
});
