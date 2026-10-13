import { themePrefix } from "virtual:theme";
import { i18n } from "discourse-i18n";

export function cropBounds(width, height, zoom, x, y) {
  const size = Math.min(width, height) / zoom;
  return {
    x: Math.max(0, Math.min(width - size, x - size / 2)),
    y: Math.max(0, Math.min(height - size, y - size / 2)),
    size,
  };
}

export function pickImage(signal) {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    const finish = (file) => {
      signal.removeEventListener("abort", abort);
      input.remove();
      resolve(file);
    };
    const abort = () => finish(null);
    signal.addEventListener("abort", abort, { once: true });
    input.addEventListener("change", () => finish(input.files[0]), {
      once: true,
    });
    input.addEventListener("cancel", abort, { once: true });
    input.click();
  });
}

export async function cropImage(file, signal) {
  const url = URL.createObjectURL(file);
  const image = new Image();
  image.src = url;
  try {
    await image.decode();
    if (signal.aborted) {
      return null;
    }
    return await new Promise((resolve, reject) => {
      const dialog = document.createElement("dialog");
      dialog.className = "blackroom-avatar-crop";
      dialog.setAttribute("aria-labelledby", "blackroom-avatar-crop-title");
      const append = (tag, key, parent = dialog) => {
        const element = document.createElement(tag);
        if (key) {
          element.textContent = i18n(themePrefix(key));
        }
        parent.append(element);
        return element;
      };
      append("h2", "title").id = "blackroom-avatar-crop-title";
      append("p", "instructions");
      const canvas = append("canvas");
      canvas.className = "blackroom-avatar-crop__preview";
      canvas.width = canvas.height = 512;
      canvas.tabIndex = 0;
      canvas.setAttribute("role", "img");
      canvas.setAttribute("aria-label", i18n(themePrefix("preview")));
      const context = canvas.getContext("2d");
      const label = append("label", "zoom");
      const slider = append("input", null, label);
      slider.type = "range";
      slider.min = "1";
      slider.max = "4";
      slider.step = "0.01";
      slider.value = "1";
      const buttons = append("div");
      buttons.className = "blackroom-avatar-crop__buttons";
      const cancel = append("button", "cancel", buttons);
      cancel.className = "btn btn-default";
      const confirm = append("button", "confirm", buttons);
      confirm.className = "btn btn-primary";
      cancel.type = confirm.type = "button";
      let x = image.naturalWidth / 2;
      let y = image.naturalHeight / 2;
      let pointer;
      let finished = false;
      const draw = () => {
        const bounds = cropBounds(
          image.naturalWidth,
          image.naturalHeight,
          Number(slider.value),
          x,
          y
        );
        x = bounds.x + bounds.size / 2;
        y = bounds.y + bounds.size / 2;
        context.clearRect(0, 0, 512, 512);
        context.drawImage(
          image,
          bounds.x,
          bounds.y,
          bounds.size,
          bounds.size,
          0,
          0,
          512,
          512
        );
      };
      const finish = (result, error) => {
        if (finished) {
          return;
        }
        finished = true;
        signal.removeEventListener("abort", abort);
        dialog.close();
        dialog.remove();
        if (error) {
          reject(error);
        } else {
          resolve(result);
        }
      };
      const abort = () => finish(null);
      signal.addEventListener("abort", abort, { once: true });
      cancel.addEventListener("click", abort);
      dialog.addEventListener("cancel", (event) => {
        event.preventDefault();
        event.stopPropagation();
        abort();
      });
      // The parent Discourse modal also handles Escape; keep it open while cancelling the crop.
      dialog.addEventListener("keydown", (event) => event.stopPropagation());
      slider.addEventListener("input", draw);
      canvas.addEventListener("pointerdown", (event) => {
        if (pointer || event.button !== 0) {
          return;
        }
        canvas.setPointerCapture(event.pointerId);
        pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
      });
      canvas.addEventListener("pointermove", (event) => {
        if (pointer?.id !== event.pointerId) {
          return;
        }
        const scale =
          Math.min(image.naturalWidth, image.naturalHeight) /
          Number(slider.value) /
          canvas.getBoundingClientRect().width;
        x -= (event.clientX - pointer.x) * scale;
        y -= (event.clientY - pointer.y) * scale;
        pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
        draw();
      });
      canvas.addEventListener("lostpointercapture", () => {
        pointer = null;
      });
      canvas.addEventListener("keydown", (event) => {
        const step =
          Math.min(image.naturalWidth, image.naturalHeight) /
          Number(slider.value) /
          50;
        const direction = {
          ArrowLeft: [-1, 0],
          ArrowRight: [1, 0],
          ArrowUp: [0, -1],
          ArrowDown: [0, 1],
        }[event.key];
        if (direction) {
          event.preventDefault();
          x += direction[0] * step;
          y += direction[1] * step;
          draw();
        }
      });
      confirm.addEventListener("click", () => {
        confirm.disabled = true;
        try {
          canvas.toBlob((blob) => {
            if (!blob) {
              finish(null, new Error("Canvas export failed"));
              return;
            }
            finish(new File([blob], "avatar.png", { type: "image/png" }));
          }, "image/png");
        } catch (error) {
          finish(null, error);
        }
      });
      document.body.append(dialog);
      dialog.showModal();
      draw();
      canvas.focus();
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}
