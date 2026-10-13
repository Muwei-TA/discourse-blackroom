import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DFilterInput from "discourse/ui-kit/d-filter-input";
import { i18n } from "discourse-i18n";
import { PODCAST_CATEGORY_ID } from "../lib/podcast-metadata";
import PodcastCover from "./podcast-cover";

export default class PodcastChannel extends Component {
  static shouldRender(args) {
    return args.category?.id === PODCAST_CATEGORY_ID;
  }

  @service blackroomPodcast;

  get episode() {
    const model = this.args.outletArgs.model;
    return (model.list?.topics || model.topics || []).find(
      (topic) => topic.category_id === PODCAST_CATEGORY_ID && topic.id !== 115
    );
  }

  get searchLabel() {
    return i18n(themePrefix("filter"));
  }

  @action
  filter(event) {
    this.blackroomPodcast.query = event.target.value;
  }

  @action
  clear() {
    this.blackroomPodcast.query = "";
  }

  @action
  play() {
    return this.blackroomPodcast.loadTopic(this.episode);
  }

  <template>
    <section class="br-podcast-channel">
      <div class="br-podcast-channel__heading"><div><h1>{{i18n
              (themePrefix "channel")
            }}
            <span>ON AIR / BLACKROOM</span></h1><p>{{i18n
              (themePrefix "tagline")
            }}</p></div><a
          class="br-podcast-channel__about"
          href="/t/topic/115"
        >{{i18n (themePrefix "about")}}</a></div>
      {{#if this.episode}}<section class="br-podcast-feature"><a
            class="raw-topic-link"
            href={{this.episode.url}}
          ><PodcastCover
              @image={{this.episode.image_url}}
              @title={{this.episode.title}}
            /></a><div class="br-podcast-feature__body"><span
              class="br-podcast-feature__kicker"
            >{{i18n (themePrefix "latest_episode")}}</span><h2><a
                class="raw-topic-link"
                href={{this.episode.url}}
              >{{this.episode.title}}</a></h2><p>{{i18n
                (themePrefix "feature_description")
              }}</p><DButton
              class="btn-primary"
              @action={{this.play}}
              @icon="play"
              @isLoading={{eq this.blackroomPodcast.loadingId this.episode.id}}
              @label={{themePrefix "listen"}}
            /><a class="raw-topic-link" href={{this.episode.url}}>{{i18n
                (themePrefix "episode_details")
              }}
              →</a></div></section>{{/if}}
      <div class="br-podcast-channel__filters"><DFilterInput
          aria-label={{this.searchLabel}}
          placeholder={{this.searchLabel}}
          @filterAction={{this.filter}}
          @onClearInput={{this.clear}}
          @value={{this.blackroomPodcast.query}}
        /><a href="/c/podcasts/49/l/bookmarks">{{i18n
            (themePrefix "saved")
          }}</a><a href="/search?q=category%3Apodcasts">{{i18n
            (themePrefix "search_all")
          }}</a></div>
    </section>
  </template>
}
