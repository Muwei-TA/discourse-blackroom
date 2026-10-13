import { apiInitializer } from "discourse/lib/api";
import PodcastCard from "../components/podcast-card";
import PodcastChannel from "../components/podcast-channel";
import PodcastDiscussion from "../components/podcast-discussion";
import PodcastPlayer from "../components/podcast-player";
import PodcastTopic from "../components/podcast-topic";
import { PODCAST_CATEGORY_ID } from "../lib/podcast-metadata";
import BlackroomPodcast from "../services/blackroom-podcast";

export default apiInitializer((api) => {
  getOwner(api.container.lookup("service:site")).register(
    "service:blackroom-podcast",
    BlackroomPodcast
  );
  const player = api.container.lookup("service:blackroom-podcast");
  api.renderInOutlet("discovery-above", PodcastChannel);
  api.renderInOutlet("topic-list-item", PodcastCard);
  api.renderInOutlet("topic-above-post-stream", PodcastTopic);
  api.renderInOutlet("topic-above-posts", PodcastDiscussion);
  api.renderInOutlet("after-main-outlet", PodcastPlayer);
  api.decorateCookedElement(
    (element, helper) => {
      if (helper.model?.topic?.category_id !== PODCAST_CATEGORY_ID) {
        return;
      }
      const audio = element.querySelector("audio");
      const pausePlayer = () => player.close();
      audio?.addEventListener("play", pausePlayer);
      return () => audio?.removeEventListener("play", pausePlayer);
    },
    { onlyStream: true }
  );
  api.registerValueTransformer("topic-list-class", ({ value, context }) =>
    context.category?.id === PODCAST_CATEGORY_ID &&
    context.listContext === "discovery"
      ? [...value, "br-podcast-list"]
      : value
  );
  api.registerValueTransformer(
    "topic-list-item-class",
    ({ value, context }) => {
      if (
        context.category?.id !== PODCAST_CATEGORY_ID ||
        context.listContext !== "discovery"
      ) {
        return value;
      }
      if (context.topic.id === 115) {
        return [...value, "br-podcast-list__about"];
      }
      return [
        ...value,
        "br-podcast-list__episode",
        ...(context.topic.title
          .toLowerCase()
          .includes(player.query.trim().toLowerCase())
          ? []
          : ["br-podcast-list__filtered"]),
      ];
    }
  );
  api.onPageChange((url) => {
    document.body.classList.toggle(
      "br-podcast-channel-page",
      /^\/c\/podcasts\/49(?:\/|\?|$)/.test(url)
    );
    const topic = api.container.lookup("controller:topic").model;
    document.body.classList.toggle(
      "br-podcast-topic",
      /^\/t\//.test(url) &&
        topic?.category_id === PODCAST_CATEGORY_ID &&
        topic.id !== 115
    );
    player.query = "";
    if (
      topic?.category_id === PODCAST_CATEGORY_ID &&
      /^\/t\/[^/]+\/\d+(?:\/1)?(?:\?|$)/.test(url) &&
      !url.includes("#")
    ) {
      window.scrollTo({ top: 0 });
    }
  });
});
import { getOwner } from "@ember/owner";
