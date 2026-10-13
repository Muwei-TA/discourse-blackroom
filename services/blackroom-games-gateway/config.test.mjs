import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { validateManifest, renderConfigs } from "./config.mjs";
const manifest = () =>
  JSON.parse(readFileSync(new URL("./games.example.json", import.meta.url)));
const state = { category_id: 10, topic_ids: { bonk: 11, skribbl: 12 } };
test("renders isolated configs and public game fields", () => {
  const source = manifest();
  source.games.push({
    ...source.games[0],
    id: "thirdgame",
    origin: "https://thirdgame.muwei.xyz",
    websocket_paths: [{ path: "/realtime", match: "exact" }],
  });
  const result = renderConfigs(
    source,
    { ...state, topic_ids: { ...state.topic_ids, thirdgame: 13 } },
    "a".repeat(64),
  );
  assert.equal(result.gateways.thirdgame.games.length, 1);
  assert.equal(result.gateways.thirdgame.games[0].port, 8080);
  assert.equal(result.forum.games[2].topic_id, 13);
  assert.equal(JSON.stringify(result.forum.games).includes("upstream"), false);
  assert.equal(
    JSON.stringify(result.forum.games).includes("a".repeat(64)),
    false,
  );
});
test("rejects invalid manifests and mismatched forum state", () => {
  for (const mutate of [
    (m) => (m.games[0].id = "test_game"),
    (m) => (m.category_slug = "1games"),
    (m) => m.games.push({ ...m.games[0] }),
    (m) => (m.games[1].origin = m.games[0].origin),
    (m) => (m.games[0].origin = "http://bonk.muwei.xyz"),
    (m) => (m.games[0].upstream = "http://secret:password@bonk:3000"),
    (m) => (m.games[0].origin += "/path"),
    (m) => (m.games[0].websocket_paths = [{ path: "//evil", match: "prefix" }]),
    (m) => (m.games[0].websocket_paths = [{ path: "/ws", match: "regex" }]),
  ]) {
    const source = manifest();
    mutate(source);
    assert.throws(() => validateManifest(source));
  }
  assert.throws(() =>
    renderConfigs(
      manifest(),
      { category_id: 10, topic_ids: { bonk: 11 } },
      "a".repeat(64),
    ),
  );
  assert.throws(() => renderConfigs(manifest(), state, "short"));
});

test("compatibility options stay private and reject broader paths", () => {
  const source = manifest();
  source.games[0].invitation_path_prefix = "/room/";
  source.games[0].bearer_jwt_paths = ["/graphql"];
  const rendered = renderConfigs(source, state, "a".repeat(64));
  assert.equal(
    rendered.gateways.bonk.games[0].invitation_path_prefix,
    "/room/",
  );
  assert.deepEqual(rendered.gateways.bonk.games[0].bearer_jwt_paths, [
    "/graphql",
  ]);
  assert.equal(rendered.forum.games[0].bearer_jwt_paths, undefined);
  assert.equal(
    rendered.gateways.skribbl.games[0].invitation_path_prefix,
    undefined,
  );
  for (const value of [
    null,
    "//evil/",
    "/",
    "/room",
    "/room/../",
    "https://evil/",
  ]) {
    assert.throws(() =>
      validateManifest({
        ...source,
        games: [{ ...source.games[0], invitation_path_prefix: value }],
      }),
    );
  }
  for (const value of [
    null,
    "/graphql",
    ["/"],
    ["/graphql/"],
    ["/graphql", "/graphql"],
    ["/graphql?x=1"],
  ]) {
    assert.throws(() =>
      validateManifest({
        ...source,
        games: [{ ...source.games[0], bearer_jwt_paths: value }],
      }),
    );
  }
});

test("CSRF cookie exception permits only unique explicit names and stays gateway-private", () => {
  const source = manifest();
  source.games[0].csrf_cookie_names = ["_csrf", "XSRF-TOKEN"];
  const result = renderConfigs(source, state, "a".repeat(64));
  assert.deepEqual(result.gateways.bonk.games[0].csrf_cookie_names, [
    "_csrf",
    "XSRF-TOKEN",
  ]);
  assert.equal(result.forum.games[0].csrf_cookie_names, undefined);
  for (const names of [["_csrf"], ["XSRF-TOKEN"], []]) {
    source.games[0].csrf_cookie_names = names;
    validateManifest(source);
  }
  for (const names of [
    ["_t"],
    ["br_game_test"],
    ["_forum_session"],
    ["_csrf", "_csrf"],
    "_csrf",
    null,
  ]) {
    source.games[0].csrf_cookie_names = names;
    assert.throws(() => validateManifest(source));
  }
});

test("localized invitation paths require the room prefix and explicit supported unique locales", () => {
  const source = manifest();
  source.games[0].invitation_path_prefix = "/room/";
  source.games[0].invitation_locales = ["en", "pt", "de", "fr", "it"];
  const result = renderConfigs(source, state, "a".repeat(64));
  assert.deepEqual(
    result.gateways.bonk.games[0].invitation_locales,
    source.games[0].invitation_locales,
  );
  assert.equal(result.forum.games[0].invitation_locales, undefined);
  for (const locales of [["en", "en"], ["zh"], ["EN"], ["../en"], "en", null]) {
    source.games[0].invitation_locales = locales;
    assert.throws(() => validateManifest(source));
  }
  source.games[0].invitation_locales = ["en"];
  delete source.games[0].invitation_path_prefix;
  assert.throws(() => validateManifest(source));
});
