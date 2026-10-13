import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { themePrefix } from "virtual:theme";
import { apiInitializer } from "discourse/lib/api";
import { validateUploadedFile } from "discourse/lib/uploads";
import { i18n } from "discourse-i18n";
import { cropImage, pickImage } from "../lib/avatar-crop";

const pending = new WeakMap();

async function selectCrop(component, file, accept) {
  pending.get(component)?.abort();
  const controller = new AbortController();
  pending.set(component, controller);
  const owner = getOwner(component);
  const siteSettings = owner.lookup("service:site-settings");
  try {
    file ??= await pickImage(controller.signal);
    if (
      !file ||
      controller.signal.aborted ||
      !validateUploadedFile(file, {
        imagesOnly: true,
        validateSize: true,
        bypassNewUserRestriction: true,
        user: owner.lookup("service:current-user"),
        siteSettings,
      })
    ) {
      return;
    }
    const cropped = await cropImage(file, controller.signal);
    if (cropped && !controller.signal.aborted) {
      await accept(cropped);
    }
  } catch {
    if (!controller.signal.aborted) {
      owner.lookup("service:dialog").alert(i18n(themePrefix("error")));
    }
  } finally {
    if (pending.get(component) === controller) {
      pending.delete(component);
    }
  }
}

export default apiInitializer((api) => {
  api.modifyClass(
    "component:d-modal",
    (Base) =>
      class extends Base {
        @action
        handleDocumentKeydown(event) {
          if (event.target.closest?.(".blackroom-avatar-crop")) {
            return;
          }
          super.handleDocumentKeydown(event);
        }
      }
  );

  api.modifyClass(
    "component:avatar-uploader",
    (Base) =>
      class extends Base {
        willDestroy() {
          pending.get(this)?.abort();
          super.willDestroy(...arguments);
        }

        @action
        chooseImage() {
          return selectCrop(this, null, (file) =>
            this.uppyUpload.addFiles([file])
          );
        }
      }
  );

  api.modifyClass(
    "component:modal/avatar-selector",
    (Base) =>
      class extends Base {
        willDestroy() {
          pending.get(this)?.abort();
          super.willDestroy(...arguments);
        }

        @action
        filesPicked(files) {
          if (!files[0]) {
            return;
          }
          return selectCrop(this, files[0], (file) =>
            super.filesPicked([file])
          );
        }
      }
  );
});
