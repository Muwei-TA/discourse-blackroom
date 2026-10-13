import assert from "node:assert/strict";
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  existsSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { prepareRelease } from "./prepare.mjs";

const manifest = {
  forum_origin: "https://discourse.muwei.xyz",
  forum_internal: "http://192.168.50.28:18180",
  category_slug: "games",
  games: [
    {
      id: "bonk",
      title: "弹球",
      description: "独立游戏",
      origin: "https://bonk.muwei.xyz",
      upstream: "http://bonk:3000",
      websocket_paths: [{ path: "/ws", match: "exact" }],
    },
  ],
};
const forumState = { category_id: 50, topic_ids: { bonk: 200 } };
const key = "a".repeat(64);

test("prepare writes private configs and returns a secret-free artifact index", () => {
  const root = mkdtempSync(path.join(tmpdir(), "games-prepare-"));
  try {
    const outputDirectory = path.join(root, "release");
    const index = prepareRelease({
      manifest,
      forumState,
      key,
      outputDirectory,
    });
    const forum = JSON.parse(
      readFileSync(path.join(outputDirectory, "forum.json"))
    );
    const gateway = JSON.parse(
      readFileSync(path.join(outputDirectory, "gateway-bonk.json"))
    );
    assert.equal(forum.gateway_key, key);
    assert.equal(forum.games[0].topic_id, 200);
    assert.equal(gateway.games[0].id, "bonk");
    assert.equal(gateway.games[0].port, 8080);
    assert.equal(statSync(outputDirectory).mode & 0o777, 0o700);
    for (const name of ["forum.json", "gateway-bonk.json", "index.json"]) {
      assert.equal(
        statSync(path.join(outputDirectory, name)).mode & 0o777,
        0o600
      );
    }
    assert.equal(JSON.stringify(index).includes(key), false);
    assert.match(index.artifacts["forum.json"], /^[a-f0-9]{64}$/);
  } finally {
    rmSync(root, { recursive: true });
  }
});

test("invalid manifest or key leaves no output directory", () => {
  const root = mkdtempSync(path.join(tmpdir(), "games-prepare-"));
  try {
    for (const bad of [
      {
        manifest: {
          ...manifest,
          games: [manifest.games[0], manifest.games[0]],
        },
      },
      { key: "short" },
    ]) {
      const outputDirectory = path.join(root, "rejected");
      assert.throws(() =>
        prepareRelease({ manifest, forumState, key, outputDirectory, ...bad })
      );
      assert.equal(existsSync(outputDirectory), false);
    }
  } finally {
    rmSync(root, { recursive: true });
  }
});
