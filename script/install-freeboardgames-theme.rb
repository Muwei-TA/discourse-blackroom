# frozen_string_literal: true

raise "production site required" unless Discourse.base_url == "https://discourse.muwei.xyz"
existing = Theme.find(6)
raise "unexpected component" unless existing.name == "BlackRoom Games" && existing.component?
theme = RemoteTheme.import_theme_from_directory("/shared/state/freeboardgames-theme-20261013", theme_id: existing&.id)
raise theme.errors.full_messages.join("; ") unless theme.persisted? && theme.component?
theme.theme_fields.each(&:ensure_baked!)
errors = theme.theme_fields.filter_map { |field| [field.name, field.error] if field.error.present? }
raise errors.inspect if errors.any?
Theme
  .where(component: false)
  .each do |parent|
    parent.add_relative_theme!(:child, theme) if parent.child_theme_ids.exclude?(theme.id)
  end
Theme.clear_cache!
Theme.notify_theme_change(theme.parent_themes.pluck(:id), all_themes: true)
puts(
  {
    theme_id: theme.id,
    fields: theme.theme_fields.count,
    errors: errors,
    parents: theme.parent_themes.pluck(:id),
  }.to_json,
)
