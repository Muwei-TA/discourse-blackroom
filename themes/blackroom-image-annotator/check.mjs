import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(
  new URL(
    "javascripts/discourse/api-initializers/image-annotator.js",
    import.meta.url
  ),
  "utf8"
)
  .replace(/^import .*;\n/gm, "")
  .replace("export default ", "");
let extension,
  render,
  uploads = 0,
  replacement,
  previewClick,
  replaceEvent;
const model = {
  reply:
    "![first|800x450](upload://abc.png)\n\n![second|800x450](upload://abc.png)",
};
const messages = [];
const original = {
  type: { name: "image" },
  attrs: { originalSrc: "upload://abc.png", alt: "keep" },
};
let current = original;
const image = {
  complete: true,
  naturalWidth: 800,
  isConnected: true,
  src: "https://canonical.test/uploads/test.png",
  decode: async () => {},
};
const view = {
  isDestroyed: false,
  nodeDOM: () => ({ querySelector: () => image }),
  state: {
    doc: { nodeAt: () => ({ eq: (node) => node === current }) },
    tr: { setNodeMarkup: (pos, type, attrs) => ({ pos, attrs }) },
  },
  dispatch: (tr) => {
    replacement = tr;
  },
};
const context = {
  apiInitializer: (callback) =>
    callback({
      container: {
        lookup: (name) => {
          if (name === "service:composer") {
            return { model };
          }
          if (name === "service:app-events") {
            return {
              trigger: (...args) => {
                replaceEvent = args;
              },
            };
          }
          return { alert: (text) => messages.push(text) };
        },
      },
      registerRichEditorExtension: (value) => {
        extension = value;
      },
      onToolbarCreate: () => {},
      addComposerImageWrapperButton: (
        label,
        className,
        icon,
        previewHandler
      ) => {
        previewClick = previewHandler;
      },
    }),
  ajax: async () => {
    uploads++;
    return { short_url: "upload://new.png", url: "/uploads/new.png" };
  },
  loadScript: async () => {},
  settings: { theme_uploads: { markerjs2: "/marker.js" } },
  i18n: (key) => key,
  themePrefix: (key) => key,
  fetch: async () => ({ ok: true, blob: async () => new Blob(["png"]) }),
  URL,
  FormData,
  Blob,
  IMAGE_MARKDOWN_REGEX:
    /!\[(.*?)\|(\d{1,4}x\d{1,4})(,\s*\d{1,3}%)?(.*?)\]\((upload:\/\/.*?)\)(?!(.*`))/g,
  markerjs2: {
    MarkerArea: class {
      settings = {};

      addRenderEventListener(callback) {
        render = callback;
      }

      getState() {
        return { markers: [{}] };
      }

      show() {}
      addCloseEventListener() {}
    },
  },
};
vm.runInNewContext(source, context);
const command = extension.commands().blackroomAnnotateImage();
assert.equal(
  command({ selection: { node: null, from: 1 } }, null, view),
  false
);
assert.equal(
  command(
    {
      selection: {
        node: {
          ...original,
          attrs: { originalSrc: "https://outside/image.png" },
        },
        from: 1,
      },
    },
    null,
    view
  ),
  false
);
command({ selection: { node: original, from: 7 } }, null, view);
await new Promise(setImmediate);
await render("data:image/png;base64,cG5n");
assert.equal(uploads, 1);
assert.equal(replacement.pos, 7);
assert.equal(replacement.attrs.originalSrc, "upload://new.png");
assert.equal(replacement.attrs.alt, "keep");
replacement = undefined;
current = null;
await render("data:image/png;base64,cG5n");
assert.equal(uploads, 1);
assert.equal(replacement, undefined);
assert.equal(messages.at(-1), "changed");
image.src = "https://canonical.test/uploads/test.png";
image.dataset = { imageIndex: "1" };
previewClick({
  preventDefault() {},
  target: {
    closest: () => ({ closest: () => ({ querySelector: () => image }) }),
  },
});
await new Promise(setImmediate);
await render("data:image/png;base64,cG5n");
assert.equal(uploads, 2);
assert.equal(replaceEvent[0], "composer:replace-text");
assert.equal(replaceEvent[1], "![second|800x450](upload://abc.png)");
assert.equal(replaceEvent[2], "![second|800x450](upload://new.png)");
assert.equal(replaceEvent[3].index, 1);
model.reply += "changed during editing";
await render("data:image/png;base64,cG5n");
assert.equal(uploads, 2);
process.stdout.write(
  "PASS: rich and Markdown selection; repeated-image targeting; metadata preserved; stale saves rejected\n"
);
