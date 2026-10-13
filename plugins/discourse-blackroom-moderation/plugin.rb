# frozen_string_literal: true

# name: discourse-blackroom-moderation
# about: Keep local AI spam suggestions in the human review queue
# version: 0.1
# authors: Muwei

module ::BlackroomModeration
  AGENT_NAME = "BlackRoom 垃圾信息初筛"

  module LocalProxyConnection
    def connect
      # Only the authenticated moderation proxy bypasses private-address filtering.
      self.ipaddr = "172.17.0.1" if address == "172.17.0.1" && port == 11_435
      super
    end
  end

  module ManualReview
    def is_spam?(output)
      result = super
      return result unless AiModerationSetting.spam&.ai_agent&.name == AGENT_NAME
      result && output.read_buffered_property(:intent) == "promotion"
    end

    def handle_spam(post, log, triggering_user_id: nil)
      post.with_lock do
        if post.trashed? || ReviewableFlaggedPost.exists?(target: post)
          log.update!(error: "Skipped deleted or previously reviewed post")
          return
        end

        reviewable =
          ReviewableFlaggedPost.needs_review!(
            target: post,
            topic: post.topic,
            created_by: flagging_user,
            reviewable_by_moderator: true,
            potential_spam: true,
            payload: {
              targets_topic: post.is_first_post?,
            },
          )
        # PostActionCreator's queue_for_review also hides posts; this path leaves disposition to staff.
        reviewable.add_score(
          flagging_user,
          PostActionType.types[:spam],
          reason: "AI 建议人工复核",
          context: log.reason.to_s.truncate(1000),
          force_review: true,
        )
        log.update!(reviewable: reviewable)
      end
    end
  end
end

after_initialize do
  FinalDestination::HTTP.prepend(BlackroomModeration::LocalProxyConnection)
  DiscourseAi::AiModeration::SpamScanner.singleton_class.prepend(BlackroomModeration::ManualReview)
end
