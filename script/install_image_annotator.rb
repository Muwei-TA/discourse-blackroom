# frozen_string_literal: true

raise "Unexpected site" unless Discourse.base_url == "https://discourse.muwei.xyz"
directory = "/shared/state/image-annotator-20261011/source"
existing = Theme.find_by(name: "BlackRoom Image Annotator")
snapshot_path = "/shared/state/image-annotator-20261011/parents-before.json"
unless File.exist?(snapshot_path)
  File.write(
    snapshot_path,
    JSON.pretty_generate(
      Theme.where(component: false).map { |t| { id: t.id, children: t.child_theme_ids } },
    ),
    mode: "wx",
    perm: 0o600,
  )
end
theme = RemoteTheme.import_theme_from_directory(directory, theme_id: existing&.id)
raise theme.errors.full_messages.join("; ") unless theme.persisted? && theme.component?
theme.theme_fields.each(&:ensure_baked!)
errors = theme.theme_fields.filter_map { |f| [f.name, f.error] if f.error.present? }
raise errors.inspect if errors.any?
if ARGV.include?("--enable")
  Theme
    .where(component: false)
    .each do |parent|
      parent.add_relative_theme!(:child, theme) if parent.child_theme_ids.exclude?(theme.id)
    end
end
Theme.clear_cache!
puts(
  {
    theme_id: theme.id,
    fields: theme.theme_fields.count,
    errors: errors,
    parents: theme.parent_themes.pluck(:id),
    snapshot: snapshot_path,
  }.to_json,
)
