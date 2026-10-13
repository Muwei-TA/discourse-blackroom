import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import BulkSelectCheckbox from "discourse/components/topic-list/bulk-select-checkbox";
import TopicLink from "discourse/components/topic-list/topic-link";
import TopicStatus from "discourse/components/topic-status";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DUserLink from "discourse/ui-kit/d-user-link";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import { PODCAST_CATEGORY_ID } from "../lib/podcast-metadata";
import PodcastCover from "./podcast-cover";

export default class PodcastCard extends Component {
  static shouldRender(args, context, owner) {
    return (
      args.topic.category_id === PODCAST_CATEGORY_ID &&
      owner
        .lookup("service:router")
        .currentRouteName?.startsWith("discovery.") &&
      owner.lookup("service:topic-tracking-state").filterCategory?.id ===
        PODCAST_CATEGORY_ID
    );
  }

  @service blackroomPodcast;

  get topic() {
    return this.args.outletArgs.topic;
  }

  get author() {
    return this.topic.creator;
  }

  get replyCount() {
    return Math.max(0, this.topic.posts_count - 1);
  }

  get playLabel() {
    return i18n(themePrefix("listen"));
  }

  @action
  play(event) {
    event?.stopPropagation();
    return this.blackroomPodcast.loadTopic(this.topic);
  }

  <template>
    <td class="br-podcast-card" colspan="5">
      <a
        class="br-podcast-card__cover-link raw-topic-link"
        href={{this.topic.url}}
      >
        <PodcastCover
          @image={{this.topic.image_url}}
          @title={{this.topic.title}}
        />
      </a>
      <div class="br-podcast-card__body">
        <div class="br-podcast-card__series">{{i18n (themePrefix "channel")}}
          <TopicStatus @context="topic-list" @topic={{this.topic}} /></div>
        <h2 class="br-podcast-card__title"><TopicLink
            class="raw-topic-link"
            @topic={{this.topic}}
          /></h2>
        <div class="br-podcast-card__footer">
          {{#if this.author}}<DUserLink @user={{this.author}}>{{dAvatar
                this.author
                imageSize="small"
              }}<span>{{or
                  this.author.name
                  this.author.username
                }}</span></DUserLink>{{/if}}
          <span>{{this.replyCount}} {{i18n (themePrefix "replies")}}</span>
          <DButton
            class="btn-flat br-podcast-card__play"
            @action={{this.play}}
            @icon="play"
            @isLoading={{eq this.blackroomPodcast.loadingId this.topic.id}}
            @translatedTitle={{this.playLabel}}
          />
        </div>
        {{#if @outletArgs.bulkSelectEnabled}}<BulkSelectCheckbox
            @isSelected={{@outletArgs.isSelected}}
            @onToggle={{@outletArgs.onBulkSelectToggle}}
            @topic={{this.topic}}
          />{{/if}}
      </div>
    </td>
  </template>
}
