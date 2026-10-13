export const PODCAST_CATEGORY_ID = 49;

export function mediaUrl(value, base = window.location.origin) {
  if (!value) {
    return null;
  }
  try {
    const url = new URL(value, base);
    return ["http:", "https:"].includes(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

export function formatTime(value) {
  const seconds = Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

export function podcastMetadata(cooked, base) {
  const document = new DOMParser().parseFromString(cooked || "", "text/html");
  const audio = document.querySelector("audio");
  const source =
    audio?.getAttribute("src") ||
    audio?.querySelector("source")?.getAttribute("src");
  const image = document.querySelector("img:not(.emoji):not(.avatar)");
  const chapters = [];
  const heading = [...document.querySelectorAll("h1,h2,h3,h4")].find((node) =>
    /时间轴|章节|chapters|timestamps/i.test(node.textContent)
  );
  for (
    let node = heading?.nextElementSibling;
    node && !/^H[1-6]$/.test(node.tagName);
    node = node.nextElementSibling
  ) {
    const content = node.cloneNode(true);
    content
      .querySelectorAll("br")
      .forEach((breakNode) => breakNode.replaceWith("\n"));
    const lines = content.querySelectorAll("li").length
      ? [...content.querySelectorAll("li")].map((item) => item.textContent)
      : content.textContent.split("\n");
    for (const line of lines) {
      const match = line.trim().match(/^((?:\d{1,3}:)?\d{1,2}:\d{2})\s+(.+)$/);
      if (!match) {
        continue;
      }
      const parts = match[1].split(":").map(Number);
      if (parts.at(-1) >= 60 || (parts.length === 3 && parts[1] >= 60)) {
        continue;
      }
      chapters.push({
        seconds: parts.reduce((total, part) => total * 60 + part, 0),
        title: match[2],
        time: match[1],
      });
    }
  }
  return {
    source: mediaUrl(source, base),
    image: mediaUrl(image?.getAttribute("src"), base),
    chapters,
  };
}
