# frozen_string_literal: true

raise "Unexpected site" unless Discourse.base_url == "https://discourse.muwei.xyz"
raise "Unexpected category" unless Category.find(49).slug == "podcasts"

root = "/shared/state/podcast-ui-20261011"
FileUtils.mkdir_p(root)
snapshot_path = "#{root}/parents-before.json"
unless File.exist?(snapshot_path)
  File.write(
    snapshot_path,
    JSON.pretty_generate(
      Theme
        .where(component: false)
        .map { |theme| { id: theme.id, children: theme.child_theme_ids } },
    ),
    mode: "wx",
    perm: 0o600,
  )
end

existing = Theme.find_by(name: "BlackRoom Podcasts")
if ARGV.include?("--disable")
  raise "Component not found" unless existing&.component?
  existing.parent_themes.each do |parent|
    parent.child_theme_ids = parent.child_theme_ids - [existing.id]
    parent.save!
  end
  Theme.clear_cache!
  puts({ theme_id: existing.id, enabled: false }.to_json)
  exit
end

theme = RemoteTheme.import_theme_from_directory("#{root}/source", theme_id: existing&.id)
raise theme.errors.full_messages.join("; ") unless theme.persisted? && theme.component?
theme.theme_fields.each(&:ensure_baked!)
errors = theme.theme_fields.filter_map { |field| [field.name, field.error] if field.error.present? }
raise errors.inspect if errors.any?
if ARGV.include?("--enable")
  Theme
    .where(component: false)
    .each do |parent|
      parent.add_relative_theme!(:child, theme) if parent.child_theme_ids.exclude?(theme.id)
    end
end
Theme.clear_cache!
Theme.notify_theme_change(theme.parent_themes.pluck(:id).presence || [theme.id], all_themes: true)
puts(
  {
    theme_id: theme.id,
    fields: theme.theme_fields.count,
    errors: errors,
    parents: theme.parent_themes.pluck(:id),
    snapshot: snapshot_path,
  }.to_json,
)
