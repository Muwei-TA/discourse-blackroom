# frozen_string_literal: true

state = JSON.parse(File.read("/shared/state/knowledge-base-created-20261007.json"))
before = JSON.parse(File.read("/shared/state/knowledge-base-settings-before-20261007.json"))
category = Category.find(state.fetch("category_id"))
index = category.doc_categories_index
raise "Documentation plugin disabled" unless SiteSetting.doc_categories_enabled
raise "Index mismatch" unless index.index_topic_id == state.fetch("index_topic_id")
raise "Missing sidebar entries" unless index.sidebar_structure.sum { |section| section[:links].size } == 4
raise "Existing categories changed" unless Category.where(id: before.fetch("categories").map(&:first)).order(:id).pluck(:id, :name, :parent_category_id) == before.fetch("categories")
raise "Existing permissions changed" unless CategoryGroup.where(category_id: before.fetch("categories").map(&:first)).order(:category_id, :group_id).pluck(:category_id, :group_id, :permission_type) == before.fetch("permissions")
raise "Login requirement changed" unless SiteSetting.login_required && SiteSetting.invite_only
raise "Knowledge base leaked into default discussion feed" if TopicQuery.new(User.find(1)).list_latest.topics.any? { |topic| topic.category_id == category.id }

checks = []
ActiveRecord::Base.transaction do
  [["blackbox_animation", 1], ["blacklight_lit", 1], [nil, 1], [nil, 0]].each do |group_name, trust_level|
    username = "kb_probe_#{SecureRandom.hex(5)}"
    user_id = User.insert_all!([{ username: username, username_lower: username, active: true,
      approved: true, admin: false, moderator: false, trust_level: trust_level }], returning: %w[id]).rows.first.first
    user = User.find(user_id)
    user.send(:create_user_stat)
    user.send(:create_user_option)
    GroupUser.insert_all!((0..trust_level).map { |level| { group_id: Group::AUTO_GROUPS.fetch(:"trust_level_#{level}"), user_id: user.id, owner: false } })
    if group_name
      GroupUser.insert_all!([{ group_id: Group.find_by!(name: group_name).id, user_id: user.id, owner: false }])
    end
    guardian = user.guardian
    raise "Member cannot read knowledge base" unless guardian.can_see_category?(category)
    raise "Member cannot write knowledge base" unless guardian.can_create_topic_on_category?(category)
    raise "Member cannot reply to directory" unless guardian.can_create_post?(index.index_topic)
    raise "Member can edit knowledge base" if guardian.can_edit_post?(index.index_topic.first_post)
    creator = PostCreator.new(user, title: "知识库写作验收 #{SecureRandom.hex(4)}", raw: "这是事务内的知识库写作验收，确认普通成员可以发表自己的知识文章，结束后回滚。#{SecureRandom.hex(8)}", category: category.id, tags: ["动画影像"], skip_jobs: true, skip_rate_limits: true)
    post = creator.create
    raise "Member publication failed: #{creator.errors.full_messages.join('; ')}" unless post&.persisted?
    raise "Author cannot edit own article" unless guardian.can_edit_post?(post)
    raise "Author revision failed" unless PostRevisor.new(post).revise!(user, { raw: post.raw + "\n\n作者补充了实践条件与验证结果。" }, silent: true)
    reply_creator = PostCreator.new(user, topic_id: index.index_topic_id, raw: "这是事务内的补充与收录申请验收，检查成员可以在目录下回复。#{SecureRandom.hex(8)}", skip_jobs: true, skip_rate_limits: true)
    reply = reply_creator.create
    raise "Member reply failed: #{reply_creator.errors.full_messages.join('; ')}" unless reply&.persisted?
    peer_name = "kb_peer_#{SecureRandom.hex(5)}"
    peer_id = User.insert_all!([{ username: peer_name, username_lower: peer_name, active: true, approved: true, admin: false, moderator: false, trust_level: 1 }], returning: %w[id]).rows.first.first
    GroupUser.insert_all!([10, 11].map { |group_id| { group_id: group_id, user_id: peer_id, owner: false } })
    other_guardian = User.find(peer_id).guardian
    raise "Peer can edit another member's article" if other_guardian.can_edit_post?(post)
    checks << { membership: group_name || "no club", trust_level: trust_level, read: true, publish: true, reply: true, own_article_revision: true, edit_others: false, edit_directory: false }
  end
  admin = User.find(1)
  raise "Admin cannot maintain knowledge base" unless admin.guardian.can_post_in_category?(category) && admin.guardian.can_edit_post?(index.index_topic.first_post)
  raise ActiveRecord::Rollback
end

puts JSON.generate(checks: checks, admin_maintenance: true, original_categories_and_permissions_preserved: true,
  temporary_accounts_rolled_back: true, index_sections: index.sidebar_structure.map { |section| section[:text] })
