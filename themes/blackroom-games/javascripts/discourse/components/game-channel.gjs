import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { themePrefix } from "virtual:theme";
import { ajax, updateCsrfToken } from "discourse/lib/ajax";
import Session from "discourse/models/session";
import { i18n } from "discourse-i18n";

export default class GameChannel extends Component {
  static shouldRender(args, context, owner) {
    const categoryId =
      owner.lookup("service:site").blackroom_games?.category_id;
    return Boolean(categoryId && args.category?.id === categoryId);
  }

  @tracked games = [];
  @tracked failed = false;
  @tracked csrf = "";
  @tracked isAlias = false;

  constructor() {
    super(...arguments);
    ajax("/blackroom-games/catalog.json")
      .then(async (catalog) => {
        if (!this.isDestroying) {
          this.games = catalog.games.map((game) => ({
            ...game,
            url: `${catalog.forum_origin}/t/topic/${game.topic_id}`,
            launchUrl: `/blackroom-games/open/${game.id}`,
            platformUrl: `${catalog.forum_origin}/blackroom-games/entry/${game.id}${this.room ? `?room=${encodeURIComponent(this.room)}` : ""}`,
          }));
          this.failed = !this.games.length;
          this.isAlias = location.origin !== catalog.forum_origin;
          if (!this.failed && !this.isAlias) {
            await updateCsrfToken();
            if (!this.isDestroying) {
              this.csrf = Session.currentProp("csrfToken");
              this.failed = !this.csrf;
            }
          }
        }
      })
      .catch(() => {
        if (!this.isDestroying) {
          this.failed = true;
        }
      });
  }

  get room() {
    return new URLSearchParams(location.search).get("room") || "";
  }

  <template>
    <section class="br-games-channel" ...attributes>
      <div class="br-games-channel__heading">
        <span class="br-games-channel__eyebrow">BLACKROOM / PLAY TOGETHER</span>
        <h1>{{i18n (themePrefix "channel")}}</h1>
        <p>{{i18n (themePrefix "tagline")}}</p>
      </div>
      {{#if this.failed}}<p role="alert">{{i18n
            (themePrefix "unavailable")
          }}</p>{{/if}}
      <div class="br-games-channel__cards">
        {{#each this.games as |game|}}
          <article class="br-games-card" data-game={{game.id}}>
            <div aria-hidden="true" class="br-games-card__art"></div>
            <div class="br-games-card__body">
              <h2>{{game.title}}</h2>
              <p>{{game.description}}</p>
              <div class="br-games-card__actions">
                {{#if this.isAlias}}
                  <a
                    class="btn btn-primary"
                    href={{game.platformUrl}}
                    rel="noopener noreferrer"
                    target="_blank"
                  >{{i18n (themePrefix "platform")}}</a>
                {{else}}
                  <form
                    action={{game.launchUrl}}
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
                    >{{i18n (themePrefix "enter")}}</button>
                  </form>
                {{/if}}
                <a href={{game.url}}>{{i18n (themePrefix "discussion")}}</a>
              </div>
            </div>
          </article>
        {{/each}}
      </div>
      <p class="br-games-channel__note">{{i18n (themePrefix "member_note")}}</p>
    </section>
  </template>
}
