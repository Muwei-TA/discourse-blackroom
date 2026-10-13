import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import Service, { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import {
  formatTime,
  PODCAST_CATEGORY_ID,
  podcastMetadata,
} from "../lib/podcast-metadata";

export default class BlackroomPodcast extends Service {
  @service dialog;

  @tracked current = null;
  @tracked duration = 0;
  @tracked elapsed = 0;
  @tracked error = null;
  @tracked loadingId = null;
  @tracked paused = true;
  @tracked query = "";
  @tracked speed = 1;

  #audio;
  #request = 0;

  constructor() {
    super(...arguments);
    this.#audio = new Audio();
    this.#audio.preload = "metadata";
    this.#audio.addEventListener("timeupdate", () => {
      this.elapsed = this.#audio.currentTime;
    });
    this.#audio.addEventListener("loadedmetadata", () => {
      this.duration = Number.isFinite(this.#audio.duration)
        ? this.#audio.duration
        : 0;
    });
    for (const event of ["play", "pause", "ended"]) {
      this.#audio.addEventListener(event, () => {
        this.paused = this.#audio.paused;
      });
    }
    this.#audio.addEventListener("error", () => {
      this.error = i18n(themePrefix("audio_error"));
    });
  }

  willDestroy() {
    this.close();
    super.willDestroy(...arguments);
  }

  get durationLabel() {
    return formatTime(this.duration);
  }

  get elapsedLabel() {
    return formatTime(this.elapsed);
  }

  get audio() {
    return this.#audio;
  }

  async loadTopic(topic) {
    const request = ++this.#request;
    this.loadingId = topic.id;
    try {
      const data = await ajax(`/t/${topic.id}.json`);
      if (request !== this.#request || this.isDestroying) {
        return;
      }
      if (data.category_id !== PODCAST_CATEGORY_ID) {
        throw new Error("Unexpected podcast category");
      }
      const firstPost = data.post_stream.posts.find(
        (post) => post.post_number === 1
      );
      const metadata = podcastMetadata(firstPost?.cooked);
      if (!metadata.source) {
        return this.dialog.alert(i18n(themePrefix("no_audio")));
      }
      await this.play({
        id: topic.id,
        title: data.title,
        url: topic.url,
        ...metadata,
      });
    } catch (error) {
      if (request === this.#request) {
        popupAjaxError(error);
      }
    } finally {
      if (request === this.#request) {
        this.loadingId = null;
      }
    }
  }

  async play(episode, seconds) {
    document
      .querySelectorAll(".br-podcast-topic .cooked audio")
      .forEach((audio) => audio.pause());
    this.error = null;
    if (this.current?.id !== episode.id || this.audio.src !== episode.source) {
      this.audio.pause();
      this.current = episode;
      this.duration = 0;
      this.elapsed = 0;
      this.audio.src = episode.source;
      this.audio.playbackRate = this.speed;
    }
    if (seconds !== undefined) {
      this.audio.currentTime = Math.max(0, seconds);
    }
    try {
      await this.audio.play();
    } catch {
      this.error = i18n(themePrefix("play_retry"));
    }
  }

  @action
  toggle() {
    if (this.paused) {
      return this.play(this.current);
    }
    this.audio.pause();
  }

  seek(seconds) {
    this.audio.currentTime = Math.max(
      0,
      Math.min(Number(seconds), this.duration)
    );
  }

  @action
  cycleSpeed() {
    const speeds = [1, 1.25, 1.5, 2];
    this.speed = speeds[(speeds.indexOf(this.speed) + 1) % speeds.length];
    this.audio.playbackRate = this.speed;
  }

  @action
  close() {
    ++this.#request;
    this.loadingId = null;
    this.#audio?.pause();
    this.#audio?.removeAttribute("src");
    this.#audio?.load();
    this.current = null;
    this.error = null;
  }
}
