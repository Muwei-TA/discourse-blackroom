# BlackRoom student club configuration

Site: https://discourse.muwei.xyz

## Verified foundation — 2026-10-07

- Audience: student club members and organizers; multiple clubs share the site and need independent spaces.
- Default language: Simplified Chinese.
- Topic titles require one character instead of six; the maximum remains 255. The prior limits are saved in `/shared/state/title-limits-before-20261007.json`.
- Chinese usernames are enabled through `unicode_usernames`. Username length remains 3–20 characters. The native validator accepted Chinese and mixed Chinese/ASCII examples and rejected spaces. The prior setting is saved in `/shared/state/unicode-usernames-before-20261007.json`.
- Login required and invitation-only registration remain enabled.
- Site description and short description now identify the student club purpose.
- Existing categories are preserved.

| Category | Purpose | Posting permission |
| --- | --- | --- |
| 社团公告 (34) | Official notices and recruitment announcements | Staff only; members can read |
| 活动交流 (35) | Activity planning, coordination, and retrospectives | Members |
| 资源共享 (36) | Learning materials and shared experience | Members |

The categories use the existing `CategoryCreator` and category permissions. Shared categories are separate from the private club spaces below.

## Available tools

- The [admin dashboard](https://discourse.muwei.xyz/admin) manages settings, groups, invitations, moderation, themes, and backups.
- The installed events, polls, chat, automation, and boards plugins provide building blocks for activities, member communication, and workflows. Installation does not imply that every feature is enabled or configured.
- The [native MCP administration page](https://discourse.muwei.xyz/admin/config/mcp) is available. The server was enabled on 2026-10-11. Subsequently, 35 tools were configured for administrators and the official ChatGPT CIMD client was registered. The user completed real OAuth; ChatGPT shows a connected account, with one active authorization and one usable token on the site. Its endpoint is `https://discourse.muwei.xyz/mcp`. Current configuration and rollback are recorded in [ChatGPT MCP notes](mcp-chatgpt.md).
- The native MCP server supports tools for content, categories, groups, moderation, themes, and ordinary site settings, subject to group scopes and the connected user's permissions. See the [official MCP guide](https://meta.discourse.org/t/connect-your-ai-apps-to-your-community-with-discourse-s-built-in-mcp-server/412755).
- Rails runners and the existing Docker deployment can apply and verify administrative changes without issuing a broad API credential.

## Relevant local skills

- `.skills/discourse-site-settings`: site setting definitions and validation.
- `.skills/discourse-frontend-conventions` and `.skills/discourse-writing-html-css`: frontend and theme implementation.
- `.skills/discourse-admin-ui`: custom admin interfaces when native configuration is insufficient.
- `.skills/discourse-screenshots`: theme and device screenshot comparisons for frontend changes.

## Recovery and verification

The configuration snapshot is `/shared/state/student-clubs-before-20261007.json` inside the app container. It contains the prior descriptions, registration policy, and category inventory.

The database and uploads backup completed successfully before configuration was applied:

`blackroom-2026-10-07-111043-v2026-10-0-latest-20261006113418.tar.gz`

Backup storage is local. The configured schedule remains every seven days, retaining up to five backups. A successful archive creation has been verified; restoration has not been tested.

上述为 2026-10-07 的历史记录。2026-10-10 已改为每日备份、保留 14 份，并完成 `/vol4/1000/backup` 归档和隔离恢复验证；当前结果与验收边界见 [备份、恢复与更新手册](resilience.md)。

Verification covered persisted settings, category permission rows, and the actual authenticated categories page. The announcement permissions are `everyone: readonly` and `staff: full`; the other two categories use ordinary member posting permissions.

## Private club spaces — 2026-10-07

| Club | Member group | Private category | Current owner |
| --- | --- | --- | --- |
| 黑箱动画社 | `blackbox_animation` (41) | 38 | `muwei` |
| 黑光文学社 | `blacklight_lit` (42) | 39 | `muwei` |

Each private category grants full access only to its own member group; administrators retain their normal access. Groups and member lists are visible to members and staff. Public admission, public exit, and membership requests are disabled. No student accounts were added or invited.

The pre-change inventory and registration settings are saved at `/shared/state/club-spaces-before-20261007.json`. Group creation used `Groups::Create`, preserving the ordinary validation and administrative audit logging.

The server-side permission check used separate temporary database users for each club and for a non-member, inside a transaction that was rolled back. Both visibility and posting were allowed only for the user's own club. Non-members were denied access to both clubs; the administrator retained access to both. The actual administrator browser page also displayed both categories. This does not substitute for testing sign-in with real student accounts.

Repeat the permission check from the application directory:

```sh
bin/rails runner script/check_club_isolation.rb
```

Assign actual club organizers as group owners and add actual members when their usernames or invitation recipients are provided.

## New member posting — verified 2026-10-07

Activated ordinary users at trust levels 0 and 1 can create topics and reply in 常规, 活动交流, and 资源共享. 社团公告 denies ordinary members both topic creation and replies. New accounts without club membership cannot post or reply in either private club category.

Invited accounts default to trust level 1. First-post mandatory approval is disabled (`approve_post_count: 0`), and the approval exemption groups include trust level 0. Separate spam, watched-word, and category rules may still queue content for review.

Topic titles require 1–255 characters. Both `min_post_length` and `min_first_post_length` are 8. Trust level 1 accounts have first-day limits of 6 topics and 30 replies; trust level 0 accounts have first-day limits of 3 topics and 10 replies.

Verification used temporary database users rolled back after checking the native Guardian topic/reply methods and approval group membership. No test topics or replies were published.
