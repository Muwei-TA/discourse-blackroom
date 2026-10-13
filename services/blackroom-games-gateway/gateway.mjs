import { readFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import { createHmac, timingSafeEqual } from "node:crypto";
import { pathToFileURL } from "node:url";

import { validateCompatibility } from "./config.mjs";

const credentialHeaders = [
  "cookie",
  "authorization",
  "x-shared-session-key",
  "x-blackroom-games-key",
  "api-key",
  "api-username",
  "api-user-id",
  "api-user-external-id",
  "user-api-key",
  "user-api-client-id",
  "discourse-user-name",
  "discourse-user-groups",
];

export function createGateway(config, game) {
  validateCompatibility(game);
  const interval = Math.min(config.checkInterval || 15000, 15000);
  if (!/^[a-f0-9]{64}$/.test(config.key || ""))
    throw new Error("Invalid gateway key");
  const cookieName = config.secureCookies ? "__Host-br_game" : "br_game_test";
  const cache = new Map();
  const live = new Map();
  const upstream = new URL(game.upstream);

  const transport = upstream.protocol === "https:" ? https : http;
  const pending = new Map();
  const waiters = [];
  let active = 0;

  async function slot() {
    if (active < 4) {
      active++;
      return;
    }
    await new Promise((resolve, reject) => {
      const waiter = {
        resolve,
        timer: setTimeout(() => {
          waiters.splice(waiters.indexOf(waiter), 1);
          reject(new Error("Authorization queue timeout"));
        }, 1000),
      };
      waiters.push(waiter);
    });
  }

  async function forum(action, data) {
    await slot();
    try {
      const response = await fetch(
        `${config.forumInternal}/blackroom-games/${action}.json`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Blackroom-Games-Key": config.key,
          },
          body: JSON.stringify({ ...data, game: game.id }),
          signal: AbortSignal.timeout(4000),
          redirect: "error",
        },
      );
      const body = await response.text();
      return { status: response.status, body };
    } finally {
      const next = waiters.shift();
      if (next) {
        clearTimeout(next.timer);
        next.resolve();
      } else active--;
    }
  }

  function signature(payload) {
    return createHmac("sha256", config.key)
      .update(`${game.id}\n${game.origin}\n${payload}`)
      .digest("hex");
  }

  function signedGrant(grant) {
    const payload = `${grant}.${Date.now() + 28800000}`;
    return `${payload}.${signature(payload)}`;
  }

  function decodeGrant(token) {
    if (
      typeof token !== "string" ||
      !/^[a-f0-9]{64}\.[0-9]{13}\.[a-f0-9]{64}$/.test(token)
    )
      return;
    const [grant, expires, mac] = token.split(".");
    if (
      Number(expires) <= Date.now() ||
      Number(expires) > Date.now() + 28800000
    )
      return;
    if (
      !timingSafeEqual(
        Buffer.from(mac, "hex"),
        Buffer.from(signature(`${grant}.${expires}`), "hex"),
      )
    )
      return;
    return grant;
  }

  function grantFrom(req) {
    return req.headers.cookie
      ?.split(";")
      .map((part) => part.trim())
      .find((part) => part.startsWith(`${cookieName}=`))
      ?.slice(cookieName.length + 1);
  }

  function revoke(token) {
    cache.delete(token);
    for (const entry of live.values())
      if (entry.grant === token) entry.destroy();
  }

  async function authorized(token, fresh = false) {
    const grant = decodeGrant(token);
    if (!grant) {
      revoke(token);
      return false;
    }
    const saved = cache.get(token);
    if (!fresh && saved && Date.now() - saved < interval) return true;
    if (pending.has(token)) return pending.get(token);
    const check = (async () => {
      try {
        if (
          (await forum("verify", { grant })).status === 204 &&
          decodeGrant(token)
        ) {
          cache.set(token, Date.now());
          return true;
        }
      } catch {}
      revoke(token);
      return false;
    })();
    pending.set(token, check);
    try {
      return await check;
    } finally {
      pending.delete(token);
    }
  }

  function requestUrl(req) {
    if (
      !req.url.startsWith("/") ||
      req.url.startsWith("//") ||
      req.url.includes("\\")
    )
      return;
    try {
      decodeURI(req.url);
      const url = new URL(req.url, game.origin);
      if (url.origin === game.origin) return url;
    } catch {}
  }

  function gameBearer(value) {
    // This is a credential forwarding filter, not authentication: the upstream
    // verifies the signature. FBG issues only userId and iat, without an issuer.
    if (typeof value !== "string" || value.length > 1024) return false;
    const match =
      /^Bearer ([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]{43})$/.exec(
        value,
      );
    if (!match) return false;
    try {
      const decode = (part) => {
        const bytes = Buffer.from(part, "base64url");
        if (bytes.toString("base64url") !== part)
          throw new Error("Noncanonical JWT");
        return JSON.parse(bytes.toString("utf8"));
      };
      const header = decode(match[1]);
      const payload = decode(match[2]);
      return (
        header?.alg === "HS256" &&
        header?.typ === "JWT" &&
        Object.keys(header).sort().join(",") === "alg,typ" &&
        payload &&
        Object.keys(payload).sort().join(",") === "iat,userId" &&
        Number.isSafeInteger(payload.userId) &&
        payload.userId > 0 &&
        Number.isSafeInteger(payload.iat) &&
        payload.iat > 0 &&
        Buffer.from(match[3], "base64url").toString("base64url") === match[3]
      );
    } catch {
      return false;
    }
  }

  function csrfCookies(values, response = false) {
    const byName = new Map();
    for (const value of values) {
      const pair = value.split(";", 1)[0].trim();
      const separator = pair.indexOf("=");
      if (separator < 0) continue;
      const name = pair.slice(0, separator);
      if (!game.csrf_cookie_names?.includes(name)) continue;
      // Ambiguous duplicate names are never forwarded, even when values agree.
      if (byName.has(name)) {
        byName.set(name, null);
        continue;
      }
      const token = pair.slice(separator + 1);
      byName.set(
        name,
        /^[A-Za-z0-9_-]{1,256}$/.test(token) ? `${name}=${token}` : null,
      );
    }
    return [...byName]
      .filter(([, pair]) => pair)
      .map(([name, pair]) =>
        response
          ? `${pair}; Path=/; SameSite=Strict${config.secureCookies ? "; Secure" : ""}${name === "_csrf" ? "; HttpOnly" : ""}`
          : pair,
      );
  }

  function headers(req, allowGameBearer = false, allowCsrf = false) {
    const result = { ...req.headers, host: new URL(game.origin).host };
    for (const name of credentialHeaders) delete result[name];
    for (const name of Object.keys(result)) {
      if (
        name === "forwarded" ||
        name === "x-real-ip" ||
        name === "proxy-authorization" ||
        name.startsWith("x-forwarded-") ||
        name.startsWith("x-auth-") ||
        name.startsWith("discourse-")
      )
        delete result[name];
    }
    if (allowGameBearer && gameBearer(req.headers.authorization))
      result.authorization = req.headers.authorization;
    if (allowCsrf) {
      const cookies = csrfCookies((req.headers.cookie || "").split(";"));
      if (cookies.length) result.cookie = cookies.join("; ");
    }
    return result;
  }

  function fail(res, status) {
    res
      .writeHead(status, {
        "Cache-Control": "no-store",
        "Content-Type": "text/plain; charset=utf-8",
      })
      .end("请从 BlackRoom 登录后开始游戏。");
  }

  const server = http.createServer(async (req, res) => {
    res.setHeader("Content-Security-Policy", "frame-ancestors 'none'");
    res.setHeader("Referrer-Policy", "no-referrer");
    if (req.headers.host !== new URL(game.origin).host) return fail(res, 421);
    const url = requestUrl(req);
    if (!url) return fail(res, 400);
    if (
      req.headers.origin &&
      req.headers.origin !== game.origin &&
      !(
        req.url === "/_blackroom/open" &&
        req.headers.origin === config.forumOrigin
      )
    )
      return fail(res, 403);
    if (req.url === "/_blackroom/open") {
      if (
        req.method !== "POST" ||
        req.headers.origin !== config.forumOrigin ||
        !req.headers["content-type"]?.startsWith(
          "application/x-www-form-urlencoded",
        )
      )
        return fail(res, 403);
      try {
        let body = "";
        for await (const chunk of req) {
          body += chunk;
          if (body.length > 2048) return fail(res, 413);
        }
        const fields = new URLSearchParams(body);
        const ticket = fields.get("ticket");
        const browser_state = fields.get("browser_state");
        const room = fields.get("room");
        if (fields.getAll("room").length > 1) return fail(res, 400);
        if (room && !/^[a-zA-Z0-9_-]{1,80}$/.test(room)) return fail(res, 400);
        if (
          !/^[a-f0-9]{64}$/.test(ticket || "") ||
          !/^[a-f0-9]{64}$/.test(browser_state || "")
        )
          return fail(res, 403);
        const response = await forum("exchange", { ticket, browser_state });
        if (response.status !== 201) return fail(res, 403);
        const { grant } = JSON.parse(response.body);
        if (!/^[a-f0-9]{64}$/.test(grant || "")) return fail(res, 502);
        const secure = config.secureCookies ? "; Secure" : "";
        res
          .writeHead(303, {
            Location: room
              ? game.invitation_path_prefix
                ? `${game.invitation_path_prefix}${room}`
                : `/?id=${encodeURIComponent(room)}`
              : "/",
            "Set-Cookie": `${cookieName}=${signedGrant(grant)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=28800${secure}`,
            "Cache-Control": "no-store",
          })
          .end();
      } catch {
        fail(res, 503);
      }
      return;
    }
    if (url.pathname === "/_blackroom/me") {
      if (req.method !== "GET") return fail(res, 405);
      const token = grantFrom(req);
      const grant = decodeGrant(token);
      if (!grant) return fail(res, 401);
      try {
        const response = await forum("profile", { grant });
        if (
          response.status === 401 ||
          response.status === 403 ||
          !decodeGrant(token)
        ) {
          revoke(token);
          return fail(res, 401);
        }
        if (response.status !== 200) return fail(res, 503);
        const { username } = JSON.parse(response.body);
        if (
          typeof username !== "string" ||
          !username ||
          username.length > 256
        ) {
          return fail(res, 502);
        }
        res
          .writeHead(200, {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
          })
          .end(JSON.stringify({ username }));
      } catch {
        fail(res, 503);
      }
      return;
    }
    if (req.url.startsWith("/_blackroom/")) return fail(res, 404);
    const grant = grantFrom(req);
    const allowed = await authorized(grant);
    const rawPath = req.url.split("?")[0];
    const invitationPrefix =
      game.invitation_path_prefix &&
      [
        game.invitation_path_prefix,
        ...(game.invitation_locales || []).map(
          (locale) => `/${locale}${game.invitation_path_prefix}`,
        ),
      ].find((prefix) => rawPath.startsWith(prefix));
    if (
      !allowed &&
      req.method === "GET" &&
      req.headers["sec-fetch-dest"] === "document" &&
      (rawPath === "/" || invitationPrefix)
    ) {
      if (rawPath === "/" && url.searchParams.getAll("id").length > 1)
        return fail(res, 400);
      const room =
        rawPath === "/"
          ? url.searchParams.get("id")
          : rawPath.slice(invitationPrefix.length);
      if (rawPath !== "/" && !/^[a-zA-Z0-9_-]{1,80}$/.test(room))
        return fail(res, 400);
      if (room && !/^[a-zA-Z0-9_-]{1,80}$/.test(room)) return fail(res, 400);
      res
        .writeHead(302, {
          Location: `${config.forumOrigin}/blackroom-games/entry/${game.id}${room ? `?room=${encodeURIComponent(room)}` : ""}`,
          "Cache-Control": "no-store",
        })
        .end();
      return;
    }
    if (res.destroyed) return;
    if (!allowed) return fail(res, 401);
    const proxy = transport.request(
      {
        hostname: upstream.hostname,
        port: upstream.port,
        path: req.url,
        method: req.method,
        headers: headers(
          req,
          game.bearer_jwt_paths?.includes(req.url.split("?")[0]),
          true,
        ),
      },
      (response) => {
        const output = {
          ...response.headers,
          "content-security-policy": [].concat(
            response.headers["content-security-policy"] || [],
            "frame-ancestors 'none'",
          ),
          "referrer-policy": "no-referrer",
        };
        delete output["set-cookie"];
        const cookies = csrfCookies(response.headers["set-cookie"] || [], true);
        if (cookies.length) output["set-cookie"] = cookies;
        delete output["x-frame-options"];
        res.writeHead(response.statusCode, output);
        response.pipe(res);
      },
    );
    live.set(res, {
      grant,
      destroy: () => {
        proxy.destroy();
        res.destroy();
      },
    });
    proxy.on("error", () => {
      if (!res.headersSent) fail(res, 502);
      else res.destroy();
    });
    proxy.setTimeout(35000, () => proxy.destroy());
    req.on("aborted", () => proxy.destroy());
    res.on("close", () => {
      live.delete(res);
      proxy.destroy();
    });
    req.pipe(proxy);
  });

  server.on("upgrade", async (req, socket, head) => {
    const reject = () =>
      socket.end("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
    const grant = grantFrom(req);
    const url = requestUrl(req);
    const validPath =
      url &&
      game.websocket_paths?.some((rule) =>
        rule.match === "exact"
          ? url.pathname === rule.path
          : rule.match === "prefix" && url.pathname.startsWith(rule.path),
      );
    if (
      req.headers.host !== new URL(game.origin).host ||
      req.headers.origin !== game.origin ||
      !validPath ||
      !(await authorized(grant))
    )
      return reject();
    if (socket.destroyed) return;
    const proxy = transport.request({
      hostname: upstream.hostname,
      port: upstream.port,
      path: req.url,
      headers: headers(req),
    });
    live.set(socket, {
      grant,
      destroy: () => {
        socket.destroy();
        proxy.destroy();
      },
    });
    proxy.once("upgrade", (response, backend, backendHead) => {
      socket.write(
        `HTTP/1.1 101 Switching Protocols\r\n${Object.entries(response.headers)
          .filter(
            ([name]) =>
              !credentialHeaders.includes(name) && name !== "set-cookie",
          )
          .map(([name, value]) => `${name}: ${value}\r\n`)
          .join("")}\r\n`,
      );
      if (backendHead.length) socket.write(backendHead);
      if (head.length) backend.write(head);
      if (!live.has(socket)) {
        backend.destroy();
        return;
      }
      live.set(socket, {
        grant,
        destroy: () => {
          socket.destroy();
          backend.destroy();
        },
      });
      backend.setTimeout(0);
      socket.on("error", () => backend.destroy());
      backend.on("error", () => socket.destroy());
      socket.on("close", () => {
        live.delete(socket);
        backend.destroy();
      });
      backend.on("close", () => socket.destroy());
      socket.pipe(backend).pipe(socket);
    });
    proxy.on("response", () => {
      proxy.destroy();
      reject();
    });
    proxy.on("error", () => socket.destroy());
    proxy.setTimeout(4000, () => proxy.destroy());
    socket.on("close", () => {
      live.delete(socket);
      proxy.destroy();
    });
    proxy.end();
  });

  let checking = false;
  const timer = setInterval(async () => {
    if (checking) return;
    checking = true;
    try {
      await Promise.all(
        [...new Set([...live.values()].map((entry) => entry.grant))].map(
          (grant) => authorized(grant, true),
        ),
      );
      for (const [grant, at] of cache)
        if (Date.now() - at > interval) cache.delete(grant);
    } finally {
      checking = false;
    }
  }, interval);
  timer.unref();
  server.requestTimeout = 10000;
  server.headersTimeout = 5000;

  return {
    server,
    close: async () => {
      clearInterval(timer);
      for (const entry of live.values()) {
        entry.destroy();
      }
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const config = JSON.parse(
    readFileSync(process.env.BLACKROOM_GATEWAY_CONFIG, "utf8"),
  );
  if (config.games?.length !== 1)
    throw new Error("Each gateway instance requires exactly one game");
  for (const game of config.games) {
    if (
      !config.secureCookies &&
      !new URL(game.origin).hostname.endsWith(".localhost")
    )
      throw new Error("HTTP test mode is restricted to localhost");
    if (config.secureCookies && !game.origin.startsWith("https://"))
      throw new Error("Secure game origins require HTTPS");
    createGateway(config, game).server.listen(game.port, "0.0.0.0");
  }
}
