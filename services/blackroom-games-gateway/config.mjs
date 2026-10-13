function check(condition, message) {
  if (!condition) throw new Error(message);
}

function origin(value, secure = false) {
  const url = new URL(value);
  check(
    ["http:", "https:"].includes(url.protocol) &&
      (!secure || url.protocol === "https:") &&
      url.origin === value &&
      !url.username &&
      !url.password,
    "Invalid origin",
  );
}

export function validateCompatibility(game) {
  check(
    game.invitation_locales === undefined ||
      (game.invitation_path_prefix === "/room/" &&
        Array.isArray(game.invitation_locales) &&
        new Set(game.invitation_locales).size ===
          game.invitation_locales.length &&
        game.invitation_locales.every((locale) =>
          ["en", "pt", "de", "fr", "it"].includes(locale),
        )),
    "Invalid invitation locales",
  );
  check(
    game.csrf_cookie_names === undefined ||
      (Array.isArray(game.csrf_cookie_names) &&
        new Set(game.csrf_cookie_names).size ===
          game.csrf_cookie_names.length &&
        game.csrf_cookie_names.every((name) =>
          ["_csrf", "XSRF-TOKEN"].includes(name),
        )),
    "Invalid CSRF cookie names",
  );
  check(
    game.invitation_path_prefix === undefined ||
      game.invitation_path_prefix === "/room/",
    "Invalid invitation path prefix",
  );
  check(
    game.bearer_jwt_paths === undefined ||
      (Array.isArray(game.bearer_jwt_paths) &&
        game.bearer_jwt_paths.length <= 1 &&
        game.bearer_jwt_paths.every((path) => path === "/graphql")),
    "Invalid game JWT paths",
  );
}

export function validateManifest(manifest) {
  origin(manifest.forum_origin, true);
  origin(manifest.forum_internal);
  check(
    /^[a-z][a-z0-9-]*$/.test(manifest.category_slug),
    "Invalid category slug",
  );
  check(
    Array.isArray(manifest.games) && manifest.games.length > 0,
    "Missing games",
  );
  const ids = new Set();
  const origins = new Set([manifest.forum_origin]);
  for (const game of manifest.games) {
    check(
      typeof game.id === "string" &&
        /^[a-z][a-z0-9-]*$/.test(game.id) &&
        !["__proto__", "constructor", "prototype"].includes(game.id) &&
        !ids.has(game.id),
      "Invalid or duplicate game id",
    );
    ids.add(game.id);
    validateCompatibility(game);
    check(
      typeof game.title === "string" &&
        game.title.trim().length > 0 &&
        typeof game.description === "string",
      "Invalid game text",
    );
    origin(game.origin, true);
    check(!origins.has(game.origin), "Duplicate game origin");
    origins.add(game.origin);
    origin(game.upstream);
    check(Array.isArray(game.websocket_paths), "Missing WebSocket rules");
    for (const rule of game.websocket_paths) {
      check(
        typeof rule.path === "string" &&
          /^\/[A-Za-z0-9_./-]*$/.test(rule.path) &&
          !rule.path.startsWith("//") &&
          !rule.path.split("/").includes("..") &&
          !rule.path.split("/").includes(".") &&
          !rule.path.startsWith("/_blackroom") &&
          ["exact", "prefix"].includes(rule.match),
        "Invalid WebSocket rule",
      );
    }
  }
  return manifest;
}

export function renderConfigs(manifest, forumState, gatewayKey) {
  validateManifest(manifest);
  check(
    typeof gatewayKey === "string" && /^[a-f0-9]{64}$/.test(gatewayKey),
    "Invalid gateway key",
  );
  check(
    Number.isSafeInteger(forumState?.category_id) && forumState.category_id > 0,
    "Invalid category id",
  );
  check(
    Object.keys(forumState.topic_ids || {}).length === manifest.games.length,
    "Mismatched topic ids",
  );
  const topics = new Set();
  const games = manifest.games.map(
    ({ id, title, description, origin: gameOrigin }) => {
      const topic_id = forumState.topic_ids[id];
      check(
        Number.isSafeInteger(topic_id) && topic_id > 0 && !topics.has(topic_id),
        "Invalid topic id",
      );
      topics.add(topic_id);
      return { id, title, description, origin: gameOrigin, topic_id };
    },
  );
  return {
    forum: {
      gateway_key: gatewayKey,
      forum_origin: manifest.forum_origin,
      category_id: forumState.category_id,
      games,
    },
    gateways: Object.fromEntries(
      manifest.games.map(
        ({
          id,
          origin: gameOrigin,
          upstream,
          websocket_paths,
          invitation_path_prefix,
          invitation_locales,
          bearer_jwt_paths,
          csrf_cookie_names,
        }) => [
          id,
          {
            forumOrigin: manifest.forum_origin,
            forumInternal: manifest.forum_internal,
            key: gatewayKey,
            secureCookies: true,
            games: [
              {
                id,
                origin: gameOrigin,
                upstream,
                websocket_paths,
                port: 8080,
                ...(invitation_path_prefix !== undefined
                  ? { invitation_path_prefix }
                  : {}),
                ...(bearer_jwt_paths !== undefined ? { bearer_jwt_paths } : {}),
                ...(invitation_locales !== undefined
                  ? { invitation_locales }
                  : {}),
                ...(csrf_cookie_names !== undefined
                  ? { csrf_cookie_names }
                  : {}),
              },
            ],
          },
        ],
      ),
    ),
  };
}
