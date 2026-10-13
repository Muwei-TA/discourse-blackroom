import { apiInitializer } from "discourse/lib/api";
import GameChannel from "../components/game-channel";
import GamePlayer from "../components/game-player";

export default apiInitializer((api) => {
  api.renderInOutlet("discovery-above", GameChannel);
  api.renderInOutlet("topic-above-post-stream", GamePlayer);
});
