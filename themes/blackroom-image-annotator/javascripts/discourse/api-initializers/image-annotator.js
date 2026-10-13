/* global markerjs2 */
import { themePrefix } from "virtual:theme";
import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import loadScript from "discourse/lib/load-script";
import { IMAGE_MARKDOWN_REGEX } from "discourse/lib/uploads";
import { i18n } from "discourse-i18n";

function supported(source) {
  return /^upload:\/\/[a-zA-Z0-9]+\.(png|jpe?g|webp)$/i.test(source || "");
}

export default apiInitializer((api) => {
  const dialog = api.container.lookup("service:dialog");
  const composer = api.container.lookup("service:composer");
  const appEvents = api.container.lookup("service:app-events");
  const message = (key) => dialog.alert(i18n(themePrefix(key)));

  async function annotate(image, isCurrent, replace) {
    let restore;
    try {
      if (!image?.complete || !image.naturalWidth || !isCurrent()) {
        return message("select_image");
      }
      await loadScript(settings.theme_uploads.markerjs2);
      if (!image.isConnected || !isCurrent()) {
        return message("changed");
      }
      // Local uploads use the canonical host even when the site is opened via an alias.
      const source = new URL(image.src);
      const response = await fetch(
        source.pathname.startsWith("/uploads/")
          ? source.pathname + source.search
          : image.src
      );
      if (!response.ok) {
        throw new Error("Image unavailable");
      }
      const originalSrc = image.src;
      const objectUrl = URL.createObjectURL(await response.blob());
      restore = () => {
        image.src = originalSrc;
        URL.revokeObjectURL(objectUrl);
      };
      image.src = objectUrl;
      await image.decode();
      if (!image.isConnected || !isCurrent()) {
        restore();
        return message("changed");
      }
      const area = new markerjs2.MarkerArea(image);
      area.addCloseEventListener(restore);
      area.settings.displayMode = "popup";
      area.renderAtNaturalSize = true;
      area.availableMarkerTypes = [
        markerjs2.ArrowMarker,
        markerjs2.FrameMarker,
        markerjs2.EllipseFrameMarker,
        markerjs2.TextMarker,
        markerjs2.HighlightMarker,
        markerjs2.FreehandMarker,
      ];
      area.addRenderEventListener(async (dataUrl) => {
        if (!area.getState().markers.length) {
          return;
        }
        try {
          if (!isCurrent()) {
            return message("changed");
          }
          const blob = await (await fetch(dataUrl)).blob();
          const data = new FormData();
          data.append("file", blob, "annotated-image.png");
          data.append("type", "composer");
          const upload = await ajax("/uploads.json", {
            type: "POST",
            data,
            processData: false,
            contentType: false,
          });
          if (!supported(upload.short_url) || !isCurrent()) {
            return message("changed");
          }
          replace(upload);
        } catch {
          message("failed");
        }
      });
      area.show();
    } catch {
      restore?.();
      message("failed");
    }
  }

  function annotateMarkdown(image) {
    const index = Number(image.dataset.imageIndex);
    const model = composer.model;
    const before = model.reply;
    const match = before.match(IMAGE_MARKDOWN_REGEX)?.[index];
    const source =
      match && new RegExp(IMAGE_MARKDOWN_REGEX.source).exec(match)?.[5];
    if (!supported(source)) {
      return message("select_image");
    }
    annotate(
      image,
      () => composer.model === model && model.reply === before,
      (upload) =>
        appEvents.trigger(
          "composer:replace-text",
          match,
          match.replace(source, upload.short_url),
          { regex: IMAGE_MARKDOWN_REGEX, index }
        )
    );
  }

  api.registerRichEditorExtension({
    commands: () => ({
      blackroomAnnotateImage: () => (state, dispatch, view) => {
        const { node, from } = state.selection;
        if (
          node?.type.name !== "image" ||
          node.attrs.placeholder ||
          !supported(node.attrs.originalSrc)
        ) {
          message("select_image");
          return false;
        }
        const dom = view.nodeDOM(from);
        const image = dom?.matches?.("img") ? dom : dom?.querySelector("img");
        annotate(
          image,
          () => !view.isDestroyed && view.state.doc.nodeAt(from)?.eq(node),
          (upload) => {
            view.dispatch(
              view.state.tr.setNodeMarkup(from, null, {
                ...node.attrs,
                src: upload.url,
                originalSrc: upload.short_url,
              })
            );
          }
        );
        return true;
      },
    }),
  });

  api.onToolbarCreate((toolbar) => {
    toolbar.addButton({
      id: "blackroom-image-annotator",
      group: "extras",
      icon: "pencil",
      title: themePrefix("annotate"),
      tabindex: 0,
      condition: () => !!api.getCurrentUser(),
      perform: (event) => {
        if (event.commands.blackroomAnnotateImage) {
          event.commands.blackroomAnnotateImage();
        } else {
          const matches = Array.from(
            event.getText().matchAll(IMAGE_MARKDOWN_REGEX)
          );
          const index =
            matches.length === 1
              ? 0
              : matches.findIndex(
                  (match) =>
                    match.index >= event.selected.start &&
                    match.index + match[0].length <= event.selected.end
                );
          const image = document.querySelector(
            `.d-editor-preview img[data-image-index="${index}"]`
          );
          if (image) {
            annotateMarkdown(image);
          } else {
            message("select_image");
          }
        }
      },
    });
  });

  api.addComposerImageWrapperButton(
    i18n(themePrefix("preview_button")),
    "blackroom-image-annotate",
    "pencil",
    (event) => {
      const button = event.target.closest(".blackroom-image-annotate");
      if (!button) {
        return;
      }
      event.preventDefault();
      const wrapper = button.closest(".image-wrapper");
      const image = wrapper.querySelector("img");
      annotateMarkdown(image);
    },
    supported
  );
});
