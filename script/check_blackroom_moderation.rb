# frozen_string_literal: true
$stdout.sync = true
Jobs.singleton_class.prepend(
  Module.new do
    def enqueue(*)
    end

    def enqueue_in(*)
    end

    def enqueue_at(*)
    end
  end,
)
PostCreator.prepend(
  Module.new do
    def store_unique_post_key
    end
  end,
)
scanner = DiscourseAi::AiModeration::SpamScanner
if scanner.singleton_class.ancestors.exclude?(BlackroomModeration::ManualReview)
  raise "plugin missing"
end
Post.transaction do
  nonce = SecureRandom.hex(4)
  id =
    User
      .insert_all!(
        [
          {
            username: "mc_#{nonce}",
            username_lower: "mc_#{nonce}",
            active: true,
            approved: true,
            trust_level: 1,
          },
        ],
        returning: %w[id],
      )
      .rows
      .first
      .first
  user = User.find(id)
  user.send(:ensure_in_trust_level_group)
  UserStat.create!(user: user, new_since: Time.zone.now) unless user.user_stat
  UserProfile.create!(user: user) unless user.user_profile
  UserOption.create!(user: user) unless user.user_option
  cases = [
    ["club", "摄影社周五在学校图书馆举办交流活动，欢迎同学报名参加。", false],
    ["scam", "先交500元保证金加我微信参加刷单返利赚钱群，每天日赚3000，名额有限！", true],
    ["warning", "警惕刷单返利诈骗，不要交保证金，请勿泄露验证码。", false],
  ]
  cases.each do |name, raw, expected|
    post =
      PostCreator.create!(
        user,
        title: "审核验收 #{name} #{nonce}",
        raw: raw,
        category: 2,
        skip_jobs: true,
        skip_rate_limits: true,
      )
    raise "not eligible" unless scanner.should_scan_post?(post)
    scanner.perform_scan(post, triggering_user_id: user.id)
    scan = AiSpamLog.where(post: post).last
    raise "no scan log" unless scan
    result = { is_spam: scan.is_spam, reason: scan.reason }
    puts(
      { case: name, expected: expected, actual: result[:is_spam], reason: result[:reason] }.to_json,
    )
    raise "wrong classification: #{name}" unless result[:is_spam] == expected
    next unless expected
    log = scan
    reviewable = log.reload.reviewable
    raise "missing queue entry" unless reviewable&.pending?
    raise "Unexpected moderation identity" unless reviewable.created_by_id == -2
    unless reviewable.reviewable_scores.pluck(:user_id).uniq == [-2]
      raise "Unexpected flagging identity"
    end
    raise "post hidden" if post.reload.hidden? || !post.topic.reload.visible?
    raise "user silenced" if user.reload.silenced?
    scanner.handle_spam(post, log, triggering_user_id: user.id)
    raise "duplicate review" unless ReviewableFlaggedPost.where(target: post).count == 1
    admin = User.where(admin: true).where("id > 0").first
    raise "admin cannot review" unless Reviewable.list_for(admin, ids: [reviewable.id]).exists?
    raise "ordinary member can review" if Reviewable.list_for(user, ids: [reviewable.id]).exists?
    result = reviewable.perform(admin, :ignore_and_do_nothing)
    raise "staff decision failed" unless result.success?
    scanner.handle_spam(post, log, triggering_user_id: user.id)
    raise "review reactivated" if reviewable.reload.pending?
    puts(
      {
        manual_review: true,
        hidden: post.reload.hidden?,
        silenced: user.reload.silenced?,
        duplicate: false,
        staff_decision: true,
      }.to_json,
    )
  end
  raise ActiveRecord::Rollback
end
puts({ passed: true, synthetic_records: "rolled back" }.to_json)
