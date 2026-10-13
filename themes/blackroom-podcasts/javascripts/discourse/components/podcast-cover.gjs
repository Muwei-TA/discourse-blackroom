import Component from "@glimmer/component";
import { themePrefix } from "virtual:theme";
import { i18n } from "discourse-i18n";
import { mediaUrl } from "../lib/podcast-metadata";

export default class PodcastCover extends Component {
  get image() {
    return mediaUrl(this.args.image);
  }

  <template>
    <div class="br-podcast-cover" ...attributes>
      {{#if this.image}}
        <img alt="" loading="lazy" src={{this.image}} />
      {{else}}
        <span class="br-podcast-cover__label">BLACKROOM / RADIO</span>
        <span class="br-podcast-cover__title">{{@title}}</span>
        <span class="br-podcast-cover__signature">{{i18n
            (themePrefix "cover_signature")
          }}</span>
      {{/if}}
    </div>
  </template>
}
