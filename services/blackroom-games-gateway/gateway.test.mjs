import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import http from "node:http";
import { createRequire } from "node:module";
import { readdirSync } from "node:fs";
import { once } from "node:events";
import { test } from "node:test";
import { createGateway } from "./gateway.mjs";

const packages = new URL("../../node_modules/.pnpm/", import.meta.url);
const installedWs = readdirSync(packages).find((name) =>
  name.startsWith("ws@"),
);
const WebSocket = createRequire(import.meta.url)(
  new URL(`${installedWs}/node_modules/ws/index.js`, packages).pathname,
);

test("protects HTTP and WebSocket, strips credentials and closes revoked connections", async () => {
  const grant = randomBytes(32).toString("hex");
  const key = randomBytes(32).toString("hex");
  let valid = true;
  let lastHeaders;
  let verifies = 0;
  const forum = http.createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    assert.equal(req.headers["x-blackroom-games-key"], key);
    assert.equal(req.headers.cookie, undefined);
    const data = JSON.parse(body);
    if (req.url.endsWith("exchange.json")) {
      if (
        data.ticket === grant &&
        data.browser_state === grant &&
        data.game === "third"
      ) {
        res.writeHead(201).end(JSON.stringify({ grant }));
      } else res.writeHead(403).end();
    } else {
      verifies++;
      res
        .writeHead(
          valid && data.grant === grant && data.game === "third" ? 204 : 403,
        )
        .end();
    }
  });
  forum.listen(0, "127.0.0.1");
  await once(forum, "listening");
  const upstream = http.createServer((req, res) => {
    lastHeaders = req.headers;
    res.setHeader("Content-Security-Policy", "connect-src 'self'");
    res.end(req.url);
  });
  upstream.on("upgrade", (req, socket) => {
    lastHeaders = req.headers;
    const server = new WebSocket.Server({ noServer: true });
    server.handleUpgrade(req, socket, Buffer.alloc(0), (ws) => {
      ws.on("message", (data) => ws.send(data));
    });
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  const game = {
    id: "third",
    websocket_paths: [{ path: "/realtime", match: "exact" }],
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
  };
  const gateway = createGateway(
    {
      forumOrigin: "http://forum.games.localhost",
      forumInternal: `http://127.0.0.1:${forum.address().port}`,
      key,
      secureCookies: false,
      checkInterval: 40,
    },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  let cookie;
  try {
    assert.equal((await fetch(game.origin)).status, 401);
    const invite = await fetch(`${game.origin}/?id=friend-room`, {
      headers: { "Sec-Fetch-Dest": "document" },
      redirect: "manual",
    });
    assert.equal(invite.status, 302);
    assert.equal(
      invite.headers.get("location"),
      "http://forum.games.localhost/blackroom-games/entry/third?room=friend-room",
    );
    const wrongHost = await new Promise((resolve) => {
      http.get(game.origin, { headers: { Host: "evil.example" } }, (res) => {
        res.resume();
        resolve(res.statusCode);
      });
    });
    assert.equal(wrongHost, 421);
    const malformed = await new Promise((resolve, reject) => {
      const request = http.get(
        {
          hostname: "127.0.0.1",
          port: gateway.server.address().port,
          path: "//[",
          headers: { Host: new URL(game.origin).host },
        },
        (response) => {
          response.resume();
          resolve(response.statusCode);
        },
      );
      request.on("error", reject);
    });
    assert.equal(malformed, 400);
    assert.equal((await fetch(game.origin)).status, 401);
    assert.equal((await fetch(`${game.origin}/_blackroom/start`)).status, 404);
    assert.equal(
      (
        await fetch(`${game.origin}/_blackroom/open`, {
          method: "POST",
          headers: {
            Origin: "https://evil.example",
            "Content-Type": "application/json",
          },
          body: "{}",
        })
      ).status,
      403,
    );
    const exchanged = await fetch(`${game.origin}/_blackroom/open`, {
      method: "POST",
      headers: {
        Origin: "http://forum.games.localhost",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        ticket: grant,
        browser_state: grant,
        room: "friend-room",
      }),
      redirect: "manual",
    });
    assert.equal(exchanged.status, 303);
    assert.equal(exchanged.headers.get("location"), "/?id=friend-room");
    assert.match(exchanged.headers.get("set-cookie"), /HttpOnly/);
    assert.equal(exchanged.headers.get("cache-control"), "no-store");
    cookie =
      exchanged.headers.get("set-cookie").split(";")[0] +
      "; _t=forum-secret-never-forward";
    const before = verifies;
    for (const value of [
      grant,
      cookie.split(";")[0].slice(13).replace(/.$/, "x"),
    ]) {
      assert.equal(
        (
          await fetch(game.origin, {
            headers: { Cookie: `br_game_test=${value}` },
          })
        ).status,
        401,
      );
    }
    assert.equal(verifies, before, "forged cookies never query the forum");
    const credentials = {
      Cookie: cookie,
      Authorization: "forged",
      Forwarded: "host=evil.example",
      "X-Forwarded-Host": "evil.example",
      "X-Shared-Session-Key": "forged",
      "X-Blackroom-Games-Key": "forged",
      "Api-Key": "forged-api",
      "User-Api-Key": "forged-user-api",
      "Api-Username": "forged-user",
      "User-Api-Client-Id": "forged-client",
    };
    const page = await fetch(`${game.origin}/?id=room123`, {
      headers: { ...credentials, "Sec-Fetch-Dest": "document" },
    });
    assert.equal(await page.text(), "/?id=room123");
    assert.equal(
      page.headers.get("content-security-policy"),
      "connect-src 'self', frame-ancestors 'none'",
    );
    assert.equal(lastHeaders.host, new URL(game.origin).host);
    assert.equal(lastHeaders.forwarded, undefined);
    assert.equal(lastHeaders["x-forwarded-host"], undefined);
    assert.equal(lastHeaders.cookie, undefined);
    assert.equal(lastHeaders.authorization, undefined);
    assert.equal(lastHeaders["x-shared-session-key"], undefined);
    assert.equal(lastHeaders["x-blackroom-games-key"], undefined);
    for (const name of [
      "api-key",
      "user-api-key",
      "api-username",
      "user-api-client-id",
    ])
      assert.equal(lastHeaders[name], undefined);
    const ws = new WebSocket(game.origin.replace("http", "ws") + "/realtime", {
      headers: credentials,
      origin: game.origin,
    });
    await once(ws, "open");
    await new Promise((resolve) => setTimeout(resolve, 4300));
    assert.equal(
      ws.readyState,
      WebSocket.OPEN,
      "idle game remains connected after the handshake timeout",
    );
    ws.send("gameplay");
    assert.equal((await once(ws, "message"))[0].toString(), "gameplay");
    assert.equal(lastHeaders.host, new URL(game.origin).host);
    assert.equal(lastHeaders.forwarded, undefined);
    assert.equal(lastHeaders["x-forwarded-host"], undefined);
    assert.equal(lastHeaders.cookie, undefined);
    for (const name of [
      "api-key",
      "user-api-key",
      "api-username",
      "user-api-client-id",
    ])
      assert.equal(lastHeaders[name], undefined);
    valid = false;
    await Promise.race([
      once(ws, "close"),
      new Promise((_, reject) =>
        setTimeout(
          () => reject(new Error("revoked WebSocket remained open")),
          2000,
        ).unref(),
      ),
    ]);
    assert.equal(
      (await fetch(game.origin, { headers: { Cookie: cookie } })).status,
      401,
    );
    assert.ok(verifies >= 2);
  } finally {
    await gateway.close();
    upstream.closeAllConnections();
    forum.closeAllConnections();
    await Promise.all([
      new Promise((resolve) => upstream.close(resolve)),
      new Promise((resolve) => forum.close(resolve)),
    ]);
  }
});

test("closes every active authorization together when the forum stops responding", async () => {
  let unavailable = false;
  const forum = http.createServer((req, res) => {
    req.resume();
    if (req.url.endsWith("exchange.json"))
      res
        .writeHead(201)
        .end(JSON.stringify({ grant: randomBytes(32).toString("hex") }));
    else if (!unavailable) res.writeHead(204).end();
  });
  forum.listen(0, "127.0.0.1");
  await once(forum, "listening");
  const upstream = http.createServer();
  const webSockets = new WebSocket.Server({ noServer: true });
  upstream.on("upgrade", (req, socket, head) =>
    webSockets.handleUpgrade(req, socket, head, () => {}),
  );
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  const game = {
    id: "bonk",
    websocket_paths: [{ path: "/ws", match: "exact" }],
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
  };
  const gateway = createGateway(
    {
      forumOrigin: "http://forum.games.localhost",
      forumInternal: `http://127.0.0.1:${forum.address().port}`,
      key: randomBytes(32).toString("hex"),
      secureCookies: false,
      checkInterval: 40,
    },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  const clients = [];
  try {
    for (let index = 0; index < 3; index++) {
      const exchange = await fetch(`${game.origin}/_blackroom/open`, {
        method: "POST",
        headers: {
          Origin: "http://forum.games.localhost",
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          ticket: "a".repeat(64),
          browser_state: "b".repeat(64),
        }),
        redirect: "manual",
      });
      const ws = new WebSocket(game.origin.replace("http", "ws") + "/ws", {
        headers: { Cookie: exchange.headers.get("set-cookie").split(";")[0] },
        origin: game.origin,
      });
      clients.push(ws);
      await once(ws, "open");
    }
    unavailable = true;
    await Promise.race([
      Promise.all(clients.map((ws) => once(ws, "close"))),
      new Promise((_, reject) =>
        setTimeout(
          () =>
            reject(
              new Error("serial verification kept a later player connected"),
            ),
          5000,
        ).unref(),
      ),
    ]);
  } finally {
    clients.forEach((ws) => ws.terminate());
    await gateway.close();
    forum.closeAllConnections();
    upstream.closeAllConnections();
    await Promise.all([
      new Promise((resolve) => forum.close(resolve)),
      new Promise((resolve) => upstream.close(resolve)),
    ]);
  }
});

function testCookie(
  key,
  game,
  grant = randomBytes(32).toString("hex"),
  expires = Date.now() + 100000,
) {
  const payload = `${grant}.${expires}`;
  const mac = createHmac("sha256", key)
    .update(`${game.id}\n${game.origin}\n${payload}`)
    .digest("hex");
  return `br_game_test=${payload}.${mac}`;
}

test("locally rejects expired and cross-game cookies and coalesces parallel resources", async () => {
  let queries = 0;
  const forum = http.createServer((req, res) => {
    req.resume();
    queries++;
    setTimeout(() => res.writeHead(204).end(), 100);
  });
  const upstream = http.createServer((req, res) => res.end("ok"));
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const key = randomBytes(32).toString("hex");
  const game = {
    id: "third",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    websocket_paths: [],
  };
  const gateway = createGateway(
    { key, forumInternal: `http://127.0.0.1:${forum.address().port}` },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  try {
    for (const cookie of [
      testCookie(key, game, undefined, Date.now() - 1),
      testCookie(key, { ...game, id: "other" }),
      testCookie(key, { ...game, origin: "https://other.example" }),
    ]) {
      assert.equal(
        (await fetch(game.origin, { headers: { Cookie: cookie } })).status,
        401,
      );
    }
    assert.equal(queries, 0);
    const cookie = testCookie(key, game);
    const results = await Promise.all(
      Array.from({ length: 20 }, () =>
        fetch(game.origin, { headers: { Cookie: cookie } }),
      ),
    );
    assert.ok(results.every((response) => response.status === 200));
    assert.equal(queries, 1);
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

test("limits authentication to four requests with a one-second queue and four-second request timeout", async () => {
  let queries = 0;
  const forum = http.createServer((req) => {
    req.resume();
    queries++;
  });
  const upstream = http.createServer((req, res) => res.end("must not reach"));
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const key = randomBytes(32).toString("hex");
  const game = {
    id: "third",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    websocket_paths: [],
  };
  const gateway = createGateway(
    { key, forumInternal: `http://127.0.0.1:${forum.address().port}` },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  try {
    const start = Date.now();
    const outcomes = await Promise.all(
      Array.from({ length: 12 }, async () => {
        const response = await fetch(game.origin, {
          headers: { Cookie: testCookie(key, game) },
        });
        return { status: response.status, elapsed: Date.now() - start };
      }),
    );
    assert.equal(queries, 4);
    assert.ok(outcomes.every((r) => r.status === 401));
    assert.equal(outcomes.filter((r) => r.elapsed < 2500).length, 8);
    assert.ok(outcomes.every((r) => r.elapsed < 5500));
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

test("revocation interrupts continuously streaming HTTP and polling responses", async () => {
  let valid = true;
  const forum = http.createServer((req, res) => {
    req.resume();
    res.writeHead(valid ? 204 : 403).end();
  });
  const upstream = http.createServer((req, res) => {
    res.writeHead(200);
    res.write("start");
    const timer = setInterval(() => res.write("data"), 10);
    res.on("close", () => clearInterval(timer));
  });
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const key = randomBytes(32).toString("hex");
  const game = {
    id: "third",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    websocket_paths: [],
  };
  const gateway = createGateway(
    {
      key,
      checkInterval: 40,
      forumInternal: `http://127.0.0.1:${forum.address().port}`,
    },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  try {
    const cookie = testCookie(key, game);
    const responses = await Promise.all(
      ["/stream", "/socket.io/?transport=polling"].map((path) =>
        fetch(game.origin + path, { headers: { Cookie: cookie } }),
      ),
    );
    const ended = responses.map(async (response) => {
      try {
        await response.text();
        return false;
      } catch {
        return true;
      }
    });
    valid = false;
    assert.deepEqual(
      await Promise.race([
        Promise.all(ended),
        new Promise((_, reject) =>
          setTimeout(
            () => reject(new Error("HTTP streams remained open")),
            2000,
          ).unref(),
        ),
      ]),
      [true, true],
    );
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

test("FBG invitation and HTTP JWT compatibility preserve the credential boundary", async () => {
  let valid = true;
  let hits = 0;
  const key = randomBytes(32).toString("hex");
  const grant = "a".repeat(64);
  const forum = http.createServer((req, res) => {
    req.resume();
    if (req.url.endsWith("exchange.json"))
      res.writeHead(201).end(JSON.stringify({ grant }));
    else res.writeHead(valid ? 204 : 403).end();
  });
  const upstream = http.createServer((req, res) => {
    hits++;
    res.setHeader("Set-Cookie", "game_cookie=secret");
    res.end(JSON.stringify(req.headers));
  });
  let wsHeaders;
  const wss = new WebSocket.Server({ noServer: true });
  upstream.on("upgrade", (req, socket, head) => {
    wsHeaders = req.headers;
    wss.handleUpgrade(req, socket, head, () => {});
  });
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const game = {
    id: "fbg",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    invitation_path_prefix: "/room/",
    bearer_jwt_paths: ["/graphql"],
    websocket_paths: [{ path: "/graphql", match: "exact" }],
  };
  const gateway = createGateway(
    {
      key,
      forumOrigin: "http://forum.games.localhost",
      forumInternal: `http://127.0.0.1:${forum.address().port}`,
      checkInterval: 40,
    },
    game,
  );
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  const jwt = (
    payload = { userId: 1, iat: 100 },
    header = { alg: "HS256", typ: "JWT" },
  ) => {
    const data = [header, payload]
      .map((part) => Buffer.from(JSON.stringify(part)).toString("base64url"))
      .join(".");
    return `Bearer ${data}.${createHmac("sha256", "synthetic-game-key").update(data).digest("base64url")}`;
  };
  const request = (path, options = {}) =>
    fetch(game.origin + path, { redirect: "manual", ...options });
  try {
    assert.equal(
      (
        await request("/en/room/Ab_-123", {
          headers: { "Sec-Fetch-Dest": "document" },
        })
      ).status,
      401,
      "localized invitations require explicit configuration",
    );
    game.invitation_locales = ["en", "pt", "de", "fr", "it"];
    for (const locale of game.invitation_locales) {
      const localized = await request(`/${locale}/room/Ab_-123`, {
        headers: { "Sec-Fetch-Dest": "document" },
      });
      assert.equal(localized.status, 302);
      assert.equal(
        localized.headers.get("location"),
        "http://forum.games.localhost/blackroom-games/entry/fbg?room=Ab_-123",
      );
    }
    for (const path of [
      "/en/room/",
      "/en/room/a/b",
      "/en/room/%61",
      "/en/room/%2f%2fevil",
      "/en/room/" + "a".repeat(81),
    ]) {
      assert.equal(
        (await request(path, { headers: { "Sec-Fetch-Dest": "document" } }))
          .status,
        400,
        path,
      );
    }
    for (const path of [
      "/zh/room/abc",
      "/EN/room/abc",
      "/%65n/room/abc",
      "/en/fr/room/abc",
    ]) {
      assert.equal(
        (await request(path, { headers: { "Sec-Fetch-Dest": "document" } }))
          .status,
        401,
        path,
      );
    }
    assert.equal((await request("/en/room/abc")).status, 401);
    const invitation = await request("/room/Ab_-123", {
      headers: { "Sec-Fetch-Dest": "document" },
    });
    assert.equal(invitation.status, 302);
    assert.equal(
      invitation.headers.get("location"),
      "http://forum.games.localhost/blackroom-games/entry/fbg?room=Ab_-123",
    );
    for (const path of [
      "/room/",
      "/room/a/b",
      "/room/%2F%2Fevil",
      "/room/%61bc",
      "/room/" + "a".repeat(81),
    ]) {
      assert.equal(
        (await request(path, { headers: { "Sec-Fetch-Dest": "document" } }))
          .status,
        400,
        path,
      );
    }
    assert.equal((await request("/room/Ab_-123")).status, 401);
    assert.equal(
      (await request("/graphql", { headers: { Authorization: jwt() } })).status,
      401,
    );
    assert.equal(hits, 0, "a game JWT cannot replace forum membership");
    const duplicate = await request("/_blackroom/open", {
      method: "POST",
      headers: {
        Origin: "http://forum.games.localhost",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: `ticket=${grant}&browser_state=${grant}&room=a&room=b`,
    });
    assert.equal(duplicate.status, 400);
    assert.equal(
      (
        await request("/?id=a&id=b", {
          headers: { "Sec-Fetch-Dest": "document" },
        })
      ).status,
      400,
    );
    const exchange = await request("/_blackroom/open", {
      method: "POST",
      headers: {
        Origin: "http://forum.games.localhost",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        ticket: grant,
        browser_state: grant,
        room: "Ab_-123",
      }),
    });
    assert.equal(exchange.status, 303);
    assert.equal(exchange.headers.get("location"), "/room/Ab_-123");
    const cookie =
      exchange.headers.get("set-cookie").split(";")[0] + "; _t=forum-secret";
    for (const path of ["/graphql", "/graphql?operation=room"]) {
      const response = await request(path, {
        headers: { Cookie: cookie, Authorization: jwt() },
      });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("set-cookie"), null);
      const headers = await response.json();
      assert.equal(headers.authorization, jwt());
      assert.equal(headers.cookie, undefined);
    }
    for (const value of [
      "Bearer forum-oauth-secret",
      jwt({ userId: 1, iat: 100, sub: "forum-user" }),
      jwt({ userId: "1", iat: 100 }),
      jwt({ userId: -1, iat: 100 }),
      jwt({ userId: 1 }),
      jwt(undefined, { alg: "none", typ: "JWT" }),
      jwt(undefined, { alg: "RS256", typ: "JWT" }),
      jwt(undefined, { alg: "HS256", typ: "JWT", kid: "other" }),
      jwt() + "=",
      "Bearer " + "a".repeat(4096),
    ]) {
      const response = await request("/graphql", {
        headers: { Cookie: cookie, Authorization: value },
      });
      assert.equal(
        (await response.json()).authorization,
        undefined,
        value.slice(0, 80),
      );
    }
    for (const path of ["/", "/graphql/", "/graphql/child", "/%67raphql"]) {
      const response = await request(path, {
        headers: { Cookie: cookie, Authorization: jwt() },
      });
      assert.equal((await response.json()).authorization, undefined, path);
    }
    delete game.bearer_jwt_paths;
    const legacy = await request("/graphql", {
      headers: { Cookie: cookie, Authorization: jwt() },
    });
    assert.equal(
      (await legacy.json()).authorization,
      undefined,
      "unconfigured games strip even valid game JWTs",
    );
    game.bearer_jwt_paths = ["/graphql"];
    const ws = new WebSocket(game.origin.replace("http", "ws") + "/graphql", {
      origin: game.origin,
      headers: { Cookie: cookie, Authorization: jwt() },
    });
    await once(ws, "open");
    assert.equal(wsHeaders.authorization, undefined);
    assert.equal(wsHeaders.cookie, undefined);
    valid = false;
    await Promise.race([
      once(ws, "close"),
      new Promise((_, reject) =>
        setTimeout(
          () => reject(new Error("JWT bypassed revocation")),
          2000,
        ).unref(),
      ),
    ]);
    assert.equal(
      (
        await request("/graphql", {
          headers: { Cookie: cookie, Authorization: jwt() },
        })
      ).status,
      401,
    );
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

test("explicit CSRF cookies round trip over HTTP without exposing forum cookies", async () => {
  const key = randomBytes(32).toString("hex");
  const grant = "a".repeat(64);
  let seen;
  const forum = http.createServer((req, res) => {
    req.resume();
    res.writeHead(204).end();
  });
  const upstream = http.createServer((req, res) => {
    seen = req.headers;
    if (req.method === "POST") {
      const passed =
        req.headers.cookie?.includes("_csrf=secret") &&
        req.headers["csrf-token"] === "token";
      res
        .writeHead(passed ? 200 : 403)
        .end(passed ? "accepted" : "invalid csrf");
    } else {
      res.setHeader(
        "Set-Cookie",
        req.url === "/duplicate"
          ? ["_csrf=one; Domain=evil.test", "_csrf=two", "XSRF-TOKEN=token"]
          : [
              "_csrf=secret; Domain=.muwei.xyz; Path=/wrong; SameSite=None",
              "XSRF-TOKEN=token; Domain=evil.test; HttpOnly; Path=/wrong",
              "_t=forum-secret",
              "br_game_test=override",
              "_forum_session=secret",
              "other=secret",
            ],
      );
      res.end("ready");
    }
  });
  forum.listen(0, "127.0.0.1");
  upstream.listen(0, "127.0.0.1");
  await Promise.all([once(forum, "listening"), once(upstream, "listening")]);
  const game = {
    id: "fbg",
    origin: "",
    upstream: `http://127.0.0.1:${upstream.address().port}`,
    csrf_cookie_names: ["_csrf", "XSRF-TOKEN"],
    websocket_paths: [],
  };
  const config = {
    key,
    secureCookies: true,
    forumInternal: `http://127.0.0.1:${forum.address().port}`,
  };
  const gateway = createGateway(config, game);
  gateway.server.listen(0, "127.0.0.1");
  await once(gateway.server, "listening");
  game.origin = `http://127.0.0.1:${gateway.server.address().port}`;
  const cookie =
    testCookie(key, game, grant).replace("br_game_test=", "__Host-br_game=") +
    "; _t=secret; _forum_session=secret; br_game_test=secret; other=secret";
  const request = (path, headers = {}, method = "GET") =>
    fetch(game.origin + path, {
      method,
      headers: { Cookie: cookie, ...headers },
    });
  try {
    const initial = await request("/");
    const cookies = initial.headers.getSetCookie();
    assert.deepEqual(cookies, [
      "_csrf=secret; Path=/; SameSite=Strict; Secure; HttpOnly",
      "XSRF-TOKEN=token; Path=/; SameSite=Strict; Secure",
    ]);
    assert.equal(seen.cookie, undefined);
    const jar =
      cookie + "; " + cookies.map((value) => value.split(";")[0]).join("; ");
    const good = await request(
      "/graphql",
      { Cookie: jar, "CSRF-Token": "token" },
      "POST",
    );
    assert.equal(good.status, 200);
    assert.equal(seen.cookie, "_csrf=secret; XSRF-TOKEN=token");
    assert.equal(
      (
        await request(
          "/graphql",
          { Cookie: jar, "CSRF-Token": "invalid" },
          "POST",
        )
      ).status,
      403,
    );
    assert.equal(
      (
        await request(
          "/graphql",
          { Cookie: jar + "; _csrf=evil", "CSRF-Token": "token" },
          "POST",
        )
      ).status,
      403,
    );
    assert.equal(seen.cookie, "XSRF-TOKEN=token");
    assert.deepEqual((await request("/duplicate")).headers.getSetCookie(), [
      "XSRF-TOKEN=token; Path=/; SameSite=Strict; Secure",
    ]);
    game.csrf_cookie_names = ["_csrf"];
    assert.deepEqual((await request("/")).headers.getSetCookie(), [
      "_csrf=secret; Path=/; SameSite=Strict; Secure; HttpOnly",
    ]);
    delete game.csrf_cookie_names;
    assert.deepEqual(
      (await request("/", { Cookie: jar })).headers.getSetCookie(),
      [],
    );
    assert.equal(seen.cookie, undefined);
    assert.equal(
      (
        await request(
          "/graphql",
          { Cookie: "_csrf=secret; XSRF-TOKEN=token", "CSRF-Token": "token" },
          "POST",
        )
      ).status,
      401,
    );
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
