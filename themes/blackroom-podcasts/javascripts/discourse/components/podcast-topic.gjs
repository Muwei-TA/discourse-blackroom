import Component from "@glimmer/component";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import DButton from "discourse/ui-kit/d-button";
import DUserLink from "discourse/ui-kit/d-user-link";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import { PODCAST_CATEGORY_ID, podcastMetadata } from "../lib/podcast-metadata";
import PodcastCover from "./podcast-cover";

export default class PodcastTopic extends Component {
  static shouldRender(args) {
    return (
      args.model?.category_id === PODCAST_CATEGORY_ID && args.model.id !== 115
    );
  }

  @service blackroomPodcast;

  get topic() {
    return this.args.outletArgs.model;
  }

  get firstPost() {
    return this.topic.postStream?.posts.find((post) => post.post_number === 1);
  }

  get metadata() {
    return podcastMetadata(this.firstPost?.cooked);
  }

  get episode() {
    return {
      id: this.topic.id,
      title: this.topic.title,
      url: this.topic.url,
      ...this.metadata,
    };
  }

  @action
  play(seconds) {
    return this.metadata.source
      ? this.blackroomPodcast.play(this.episode, seconds)
      : this.blackroomPodcast.loadTopic(this.topic);
  }

  @action
  bookmark() {
    return getOwner(this).lookup("controller:topic").toggleBookmark();
  }

  <template>
    <section class="br-podcast-topic-header">
      <a class="br-podcast-topic-header__back" href="/c/podcasts/49">←
        {{i18n (themePrefix "back")}}</a>
      <div class="br-podcast-topic-header__hero"><PodcastCover
          @image={{or this.topic.image_url this.metadata.image}}
          @title={{this.topic.title}}
        /><div class="br-podcast-topic-header__body"><span
            class="br-podcast-feature__kicker"
          >BLACKROOM / {{i18n (themePrefix "channel")}}</span><h1
          >{{this.topic.title}}</h1>{{#if this.firstPost}}<div
              class="br-podcast-topic-header__author"
            ><DUserLink @username={{this.firstPost.username}}>{{dAvatar
                  this.firstPost
                  imageSize="small"
                }}{{or
                  this.firstPost.name
                  this.firstPost.username
                }}</DUserLink></div>{{/if}}<div
            class="br-podcast-topic-header__actions"
          ><DButton
              class="btn-primary"
              @action={{fn this.play undefined}}
              @icon="play"
              @label={{themePrefix "listen"}}
            /><DButton
              class="btn-default"
              @action={{this.bookmark}}
              @icon="bookmark"
              @label={{themePrefix "bookmark"}}
            /></div></div></div>
      {{#if this.metadata.chapters.length}}<nav
          aria-label={{i18n (themePrefix "chapters")}}
          class="br-podcast-chapters"
        >{{#each this.metadata.chapters as |chapter|}}<DButton
              class="btn-flat"
              @action={{fn this.play chapter.seconds}}
              @translatedLabel={{concat chapter.time "  " chapter.title}}
            />{{/each}}</nav>{{/if}}
    </section>
  </template>
}
