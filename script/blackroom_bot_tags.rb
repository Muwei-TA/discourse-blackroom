# frozen_string_literal: true

module BlackroomBotTags
  def ensure_tag(post, editor, tag)
    return if post.topic.tags.exists?(name: tag)
    raise "Cannot tag managed publication" unless editor.guardian.can_edit_post?(post)
    tags = post.topic.tags.pluck(:name) | [tag]
    revisor = PostRevisor.new(post)
    unless revisor.revise!(editor, { tags: tags }, bypass_bump: true, silent: true) &&
             post.topic.reload.tags.exists?(name: tag)
      raise "Publication tagging failed"
    end
  end
end
