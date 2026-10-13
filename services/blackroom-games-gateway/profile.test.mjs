import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import http from "node:http";
import { once } from "node:events";
import { test } from "node:test";
import { createGateway } from "./gateway.mjs";

test("profile is current, private, bound to the game and never forwarded upstream", async () => {
  const key = randomBytes(32).toString("hex");
  const grants = [
    randomBytes(32).toString("hex"),
    randomBytes(32).toString("hex"),
  ];
  const names = new Map([
    [grants[0], "中文玩家"],
    [grants[1], "second_player"],
  ]);
  let profileCalls = 0;
  let upstreamCalls = 0;
  let profileStatus = 200;
  let malformed = false;
  const forum = http.createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    assert.equal(req.headers["x-blackroom-games-key"], key);
    assert.equal(req.headers.cookie, undefined);
    const data = JSON.parse(body);
    if (req.url === "/blackroom-games/profile.json") {
      profileCalls++;
      assert.equal(data.game, "bonk");
      const username = names.get(data.grant);
      const status = username ? profileStatus : 403;
      res
        .writeHead(status, { "Content-Type": "application/json" })
        .end(
          JSON.stringify(
            malformed
              ? { username: null }
              : { username, email: "must-not-leak@example.test" }
          )
        );
    } else res.writeHead(204).end();
  });
  const upstream = http.createServer((_req, res) => {
    upstreamCalls++;
    res.end("game");
  });
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const game = {
    id: "bonk",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    websocket_paths: [],
  };
  const gateway = createGateway(
    {
      key,
      forumInternal: `http://127.0.0.1:${forum.address().port}`,
      forumOrigin: "https://forum.example.test",
      secureCookies: false,
    },
    game
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  const cookie = (grant, id = game.id) => {
    const payload = `${grant}.${Date.now() + 60000}`;
    return `br_game_test=${payload}.${createHmac("sha256", key).update(`${id}\n${game.origin}\n${payload}`).digest("hex")}`;
  };
  const request = (extra = {}) =>
    fetch(`${game.origin}/_blackroom/me?username=forged`, {
      headers: { Cookie: cookie(grants[0]), ...extra.headers },
      ...extra,
      redirect: "manual",
    });
  try {
    for (const grant of grants) {
      const response = await request({ headers: { Cookie: cookie(grant) } });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("cache-control"), "no-store");
      assert.equal(response.headers.get("access-control-allow-origin"), null);
      assert.deepEqual(await response.json(), { username: names.get(grant) });
    }
    names.set(grants[0], "改名后玩家");
    assert.deepEqual(await (await request()).json(), {
      username: "改名后玩家",
    });
    const calls = profileCalls;
    for (const value of [
      "",
      "br_game_test=forged",
      cookie(grants[0], "skribbl"),
    ]) {
      assert.equal((await request({ headers: { Cookie: value } })).status, 401);
    }
    assert.equal(profileCalls, calls);
    assert.equal((await request({ method: "POST" })).status, 405);
    assert.equal(
      (
        await request({
          headers: {
            Cookie: cookie(grants[0]),
            Origin: "https://other.example.test",
          },
        })
      ).status,
      403
    );
    names.delete(grants[0]);
    assert.equal((await request()).status, 401);
    names.set(grants[0], "restored");
    profileStatus = 503;
    assert.equal((await request()).status, 503);
    profileStatus = 200;
    malformed = true;
    assert.equal((await request()).status, 502);
    assert.equal(upstreamCalls, 0);
  } finally {
    await gateway.close();
    forum.closeAllConnections();
    upstream.closeAllConnections();
    await Promise.all([
      new Promise((r) => forum.close(r)),
      new Promise((r) => upstream.close(r)),
    ]);
  }
});
