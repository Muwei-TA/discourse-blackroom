import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { themePrefix } from "virtual:theme";
import { updateCsrfToken } from "discourse/lib/ajax";
import Session from "discourse/models/session";
import { i18n } from "discourse-i18n";

export default class GamePlayer extends Component {
  static shouldRender(args) {
    return Boolean(args.model?.blackroom_game);
  }

  @tracked csrf = "";
  @tracked failed = false;

  constructor() {
    super(...arguments);
    if (!this.game || this.isAlias) {
      return;
    }
    updateCsrfToken()
      .then(() => {
        if (!this.isDestroying) {
          this.csrf = Session.currentProp("csrfToken");
          this.failed = !this.csrf;
        }
      })
      .catch(() => {
        if (!this.isDestroying) {
          this.failed = true;
        }
      });
  }

  get game() {
    return this.args.outletArgs?.model?.blackroom_game;
  }

  get isAlias() {
    return location.origin !== this.game.forum_origin;
  }

  get platformUrl() {
    const url = new URL(
      `/t/topic/${this.game.topic_id}`,
      this.game.forum_origin
    );
    if (this.room) {
      url.searchParams.set("room", this.room);
    }
    return url.href;
  }

  get launchUrl() {
    return `/blackroom-games/open/${this.game.id}`;
  }

  get room() {
    return new URLSearchParams(location.search).get("room") || "";
  }

  <template>
    {{#if this.game}}
      <section class="br-games-player" ...attributes>
        <div class="br-games-player__toolbar">
          <div><h2>{{this.game.title}}</h2><p
            >{{this.game.description}}</p></div>
          {{#if this.isAlias}}
            <a class="btn btn-primary" href={{this.platformUrl}}>{{i18n
                (themePrefix "platform")
              }}</a>
          {{else}}
            <form
              action={{this.launchUrl}}
              method="post"
              rel="noopener"
              target="_blank"
            >
              <input
                name="authenticity_token"
                type="hidden"
                value={{this.csrf}}
              />
              <input name="room" type="hidden" value={{this.room}} />
              <button
                class="btn btn-primary"
                disabled={{not this.csrf}}
                type="submit"
              >
                {{i18n (themePrefix "start")}}
              </button>
            </form>
          {{/if}}
        </div>
        {{#if this.failed}}<p role="alert">{{i18n
              (themePrefix "unavailable")
            }}</p>{{/if}}
        <p class="br-games-player__note">{{i18n (themePrefix "idle")}}</p>
      </section>
    {{/if}}
  </template>
}
