import Component from "@glimmer/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { themePrefix } from "virtual:theme";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { PODCAST_CATEGORY_ID } from "../lib/podcast-metadata";

export default class PodcastDiscussion extends Component {
  static shouldRender(args) {
    return (
      args.model?.category_id === PODCAST_CATEGORY_ID && args.model.id !== 115
    );
  }

  get topic() {
    return this.args.outletArgs.model;
  }

  get replyCount() {
    return Math.max(0, this.topic.posts_count - 1);
  }

  @action
  reply() {
    return getOwner(this).lookup("controller:topic").replyToPost();
  }

  <template>
    <aside class="br-podcast-discussion"><h2>{{i18n (themePrefix "discussion")}}
        <span>{{this.replyCount}}
          {{i18n (themePrefix "replies")}}</span></h2>{{#unless
        this.replyCount
      }}<p>{{i18n (themePrefix "no_replies")}}</p>{{/unless}}{{#if
        this.topic.details.can_create_post
      }}<DButton
          class="btn-primary"
          @action={{this.reply}}
          @icon="reply"
          @label={{themePrefix "reply"}}
        />{{/if}}</aside>
  </template>
}
