# BlackRoom 第三方登录接入

## 当前状态（2026-10-09）

目标平台：Google、微信、QQ。用户确认三个平台均尚未申请对应应用。

本次现场核对：线上 `app` 容器内 Google 登录关闭、Client ID / Client Secret 未配置，已启用认证器列表为空。本地密码登录及邮件登录开启，`invite_only`、`login_required` 为 true。已安装插件中没有微信或 QQ 登录插件。本次没有修改线上登录配置或安装插件。

Google 复用 Discourse 内置认证器。微信、QQ 先申请网站应用，再确定兼容当前运行版本的认证器；不能把安装旧插件或显示登录按钮视为接入完成。

## 共同填写材料

| 字段 | 建议值或来源 |
| --- | --- |
| 应用名称 | BlackRoom |
| 网站首页 | `https://discourse.muwei.xyz` |
| 应用简介 | 为学生社团提供公告、活动交流、写作与资源共享的社区 |
| 网站域名 | `discourse.muwei.xyz` |
| 支持邮箱、管理员联系人 | 用户自行选择真实可接收邮件的联系方式 |
| 开发者主体、实名或组织资质、备案材料 | 用户按平台当前要求提供真实材料 |
| 隐私政策、用户协议、应用图标 | 提交前确认现有站点实际页面及材料，不填写未核实的链接 |

若平台要求审核人员访问站点，由用户确定必要的审核方式；不自动关闭邀请注册、登录要求或公网入口保护。

## Google

1. 打开 [Google Auth Platform](https://console.cloud.google.com/auth/overview)。建议建立专用 `BlackRoom` 项目；当前浏览器默认选中的 Gemini 项目不作为本站默认接入项目。
2. 配置品牌信息：应用名称 BlackRoom，支持邮箱及开发者联系邮箱由用户指定；面向不同 Google 账号时选择 External。
3. 创建 OAuth 客户端，应用类型选择 **Web application**。
4. Authorized JavaScript origins 填 `https://discourse.muwei.xyz`。
5. Authorized redirect URIs 精确填 `https://discourse.muwei.xyz/auth/google_oauth2/callback`。
6. 仅申请登录所需的基本身份、邮箱和个人资料范围，不申请 Gmail、Drive 或其他业务权限。按控制台当前提示处理测试用户、发布状态及必要验证。
7. 用户直接在 [Discourse 社交登录设置](https://discourse.muwei.xyz/admin/config/login-and-authentication/authenticators) 填 `google_oauth2_client_id` 和 `google_oauth2_client_secret`，保存后再启用 `enable_google_oauth2_logins`。

创建及保存凭据的步骤由用户完成。不要把客户端 JSON、密钥或授权码发送到聊天、Git 或工具日志。

参考：[Discourse Google 接入指南](https://meta.discourse.org/t/configure-google-login-for-discourse/15858)、[Google Web Server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server)、[Google Audience 配置说明](https://support.google.com/cloud/answer/15549945)。

## 微信

- 用户打开 [微信开放平台](https://open.weixin.qq.com/)，进入网站应用申请流程，按平台当前要求完成主体认证、材料与微信登录审核。
- 申请的是本站的网站应用登录能力；不能直接把其他小程序的 AppID / AppSecret 当作网站扫码登录凭据。
- 拟使用的本站回调域为 `discourse.muwei.xyz`。精确回调路径需在最终认证器确定后核对，当前不提供未经验证的路径。
- 已发现 [社区微信二维码登录插件](https://github.com/mooosu/wechat_qrconnect) 与其 [Discourse 介绍](https://meta.discourse.org/t/login-plugin-wechat-login-plugin/38876)，尚未验证与当前 Discourse 的兼容性，不直接部署。
- 本次自动浏览器访问微信开放平台被安全策略阻止；不得用另一浏览器、CLI 或代理绕过。主体条件、费用及审核材料需由用户在官方页面核对，当前未核实。

## QQ

- 用户打开 [QQ 互联](https://connect.qq.com/)，登录后在应用管理中申请 **网站应用**，不选择 QQ 机器人或 AI 互联 Token。
- 按平台当前要求填写网站与开发者材料，确认审核状态和可登录的用户范围。
- 精确回调地址需在最终 QQ 认证器确定后填写；当前未发现已安装的 QQ 登录插件，不能直接假定 `/auth/qq/callback` 已可用。
- 官方 [文档入口](https://wiki.connect.qq.com/) 本次未取得可用的接入文档正文，具体资质、备案和审核条件以登录后的官方页面为准。

## 接入与验收契约

- 保留密码和邮件登录作为现有入口；保留邀请注册规则和社团分区权限。
- 微信、QQ 的昵称不作为账号匹配凭据，不把 QQ 邮箱推断为已验证邮箱。已有用户先在登录状态下绑定第三方账号，再验证退出后的登录。
- 每个平台分别核对应用配置、认证器启用状态、登录页面按钮、授权回调及真实账号登录；缺失凭据或审核时报告待完成，不发布“已支持”公告。
- 未绑定的第三方用户不能绕过邀请要求或自动加入社团。启用后的权限验收覆盖本社团成员、其他社团成员、非成员及管理员。
- 功能上线且完成用户可见验收后，按 [更新助手发布契约](blackroom-updates-bot.md) 发布公告和教程。
