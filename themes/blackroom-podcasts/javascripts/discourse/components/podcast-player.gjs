import Component from "@glimmer/component";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { themePrefix } from "virtual:theme";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import PodcastCover from "./podcast-cover";

export default class PodcastPlayer extends Component {
  @service blackroomPodcast;

  reserveSpace = modifier((element) => {
    document.body.classList.add("br-podcast-playing");
    this.blackroomPodcast.audio.hidden = true;
    element.append(this.blackroomPodcast.audio);
    return () => document.body.classList.remove("br-podcast-playing");
  });

  @action
  seek(event) {
    this.blackroomPodcast.seek(event.target.value);
  }

  @action
  rewind() {
    this.blackroomPodcast.seek(this.blackroomPodcast.elapsed - 5);
  }

  <template>
    {{#if this.blackroomPodcast.current}}
      <section
        aria-label={{i18n (themePrefix "player")}}
        class="br-podcast-player"
        {{this.reserveSpace}}
      >
        <a
          class="br-podcast-player__episode raw-topic-link"
          href={{this.blackroomPodcast.current.url}}
        ><PodcastCover
            @image={{this.blackroomPodcast.current.image}}
            @title="BR"
          /><span>{{this.blackroomPodcast.current.title}}<small>BlackRoom ·
              {{i18n (themePrefix "channel")}}</small></span></a>
        <div class="br-podcast-player__transport"><DButton
            class="btn-flat"
            @action={{this.rewind}}
            @icon="backward"
            @title={{themePrefix "rewind"}}
          /><DButton
            class="btn-primary"
            @action={{fn this.blackroomPodcast.toggle}}
            @icon={{if this.blackroomPodcast.paused "play" "pause"}}
            @title={{if
              this.blackroomPodcast.paused
              (themePrefix "play")
              (themePrefix "pause")
            }}
          /><time>{{this.blackroomPodcast.elapsedLabel}}</time><input
            aria-label={{i18n (themePrefix "progress")}}
            max={{this.blackroomPodcast.duration}}
            min="0"
            step="0.1"
            type="range"
            value={{this.blackroomPodcast.elapsed}}
            {{on "input" this.seek}}
          /><time>{{this.blackroomPodcast.durationLabel}}</time></div>
        <div class="br-podcast-player__actions"><DButton
            class="btn-flat"
            @action={{fn this.blackroomPodcast.cycleSpeed}}
            @title={{themePrefix "speed"}}
            @translatedLabel={{concat this.blackroomPodcast.speed "×"}}
          /><DButton
            class="btn-flat"
            @action={{fn this.blackroomPodcast.close}}
            @icon="xmark"
            @title={{themePrefix "close"}}
          /></div>
        {{#if this.blackroomPodcast.error}}<p
            class="br-podcast-player__error"
          >{{this.blackroomPodcast.error}}</p>{{/if}}
      </section>
    {{/if}}
  </template>
}
