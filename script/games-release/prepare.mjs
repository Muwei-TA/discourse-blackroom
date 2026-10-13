import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { renderConfigs } from "../../services/blackroom-games-gateway/config.mjs";

export function prepareRelease({ manifest, forumState, key, outputDirectory }) {
  if (!/^[a-f0-9]{64}$/.test(key)) throw new Error("Invalid gateway key");
  if (!path.isAbsolute(outputDirectory))
    throw new Error("Output directory must be absolute");
  const { forum, gateways } = renderConfigs(manifest, forumState, key);
  const files = { "forum.json": forum };
  for (const [id, config] of Object.entries(gateways))
    files[`gateway-${id}.json`] = config;
  mkdirSync(outputDirectory, { recursive: true, mode: 0o700 });
  chmodSync(outputDirectory, 0o700);
  const index = { artifacts: {} };
  for (const [name, data] of Object.entries(files)) {
    const content = JSON.stringify(data, null, 2) + "\n";
    const destination = path.join(outputDirectory, name);
    const temporary = destination + ".tmp";
    writeFileSync(temporary, content, { mode: 0o600 });
    chmodSync(temporary, 0o600);
    renameSync(temporary, destination);
    index.artifacts[name] = createHash("sha256").update(content).digest("hex");
  }
  writeFileSync(
    path.join(outputDirectory, "index.json"),
    JSON.stringify(index, null, 2) + "\n",
    { mode: 0o600 }
  );
  chmodSync(path.join(outputDirectory, "index.json"), 0o600);
  return index;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const [manifestFile, stateFile, keyFile, outputDirectory] =
    process.argv.slice(2);
  if (!manifestFile || !stateFile || !keyFile || !outputDirectory) {
    throw new Error(
      "Usage: prepare.mjs MANIFEST STATE KEY_FILE OUTPUT_DIRECTORY"
    );
  }
  const index = prepareRelease({
    manifest: JSON.parse(readFileSync(manifestFile, "utf8")),
    forumState: JSON.parse(readFileSync(stateFile, "utf8")),
    key: readFileSync(keyFile, "utf8").trim(),
    outputDirectory,
  });
  console.log(JSON.stringify(index));
}
