# JEV 本地审核服务

## 目标与边界

用户选择：疑似违规送入 Discourse 人工审核队列，由管理员决定；不自动删帖或封号。
JEV 本身是文本分类 API，不带 Discourse 连接器。正式接入前需要通过中文合成样本验收，再验证审核队列、重复处理、服务故障和分区权限。

## 部署制品

- NAS 路径：`/vol1/docker/blackroom-jev`
- Compose 与验收脚本：[本地制品目录](../../work/blackroom-jev/)
- 官方固定版本：[`jevos-v4`](https://github.com/feder-cr/jev/releases/tag/jevos-v4)
- 二进制与模型压缩包通过该 release 的 `SHA256SUMS.txt` 校验。
- 基础镜像为现场已有 Ubuntu 24.04，按 digest 固定版本；官方二进制和模型只读挂载，不依赖重新编译。
- 运行文件在系统 NVMe：`/home/muwei/blackroom-jev-runtime/jevos-v4/jev`；保留 `/vol1` 原下载文件。原 Btrfs 挂载下曾观察到 JEV 长期处于 `D / disk sleep`。
- 活跃容器：`blackroom-jev-nvme`；接口：`http://192.168.50.28:18018/v1/systemone`。
- 当前活跃容器已由 Compose 管理，重启策略为 `unless-stopped`。资源扩容时重建了 JEV 容器，未重建 Discourse。
- 原 4 CPU／3 GB／4 线程容器 `blackroom-jev-4cpu-3gb` 已停止，重启策略为 `no`，保留用于回退；旧配置在 NVMe 的 `compose-4cpu-3gb.yaml`。
- 限制：12 CPU、8 GB RAM、12 推理线程、256 PID、非 root、只读根文件系统，日志最多 3 × 10 MB；state-cache=0。
- `.env` 仅保存在 NAS，权限 `0600`；不要展示内容。`JEV_API_KEY` 在 NAS 生成，不传到聊天或 Git。
- 使用现有默认 bridge；NAS 自动分配的 Docker 网段池已耗尽，不新增网络。
- 未配置公网入口。中文验收仅使用合成文本。

## 操作

```sh
ssh nas 'cd /vol1/docker/blackroom-jev && docker compose up -d'
ssh nas 'curl --max-time 10 -fsS http://192.168.50.28:18018/health'
ssh nas 'cd /vol1/docker/blackroom-jev && python3 check_service.py'
```

验收脚本检查无凭据请求返回 401、概率取值范围及 12 条中英文合成样本。结果保存在 NAS 的 `acceptance-results.json`。它不等同于真实帖子审核验收；少量样本也不足以证明长期误报率。

停止本服务（保留二进制、模型、凭据与结果）：

```sh
docker --context nas stop --timeout 10 blackroom-jev-nvme
```

## 2026-10-09 现场状态

下载及 SHA-256 校验完成。首次 BuildKit 和传统镜像构建均迟缓，已停止本次构建客户端，改用既有基础镜像与只读挂载。

后续核验中，旧容器虽然已运行，但 JEV 卡在模型加载。NVMe 新副本重新通过官方校验，独立容器最终启动，`/health` 返回 `status=ready`、`model=jevos-v4`，模型 fingerprint 为 `6afd085ed8676530c4e4f0dfd0e532b5903f6445742979b342c30ea3b3b2af53`。已确认无凭据调用返回 401，活跃容器为非 root、只读、4 CPU、3 GB RAM、重启计数 0。

第一轮综合规则的 12 条样本在 0.5 阈值下误报 2 条正常内容、漏报英文诈骗；0.8 阈值漏报全部 6 条违规内容。结果保存在 `/home/muwei/blackroom-jev-runtime/acceptance-composite-results.json`。简短规则复测结果保存在服务目录的 `acceptance-results.json`，包含 `Server-Timing`，仍观察到英文诈骗与正常内容得分重叠。不能仅调整阈值后直接接入生产。

当前合成请求约 14–22 秒，服务端计时显示推理本身占据主要耗时；NAS I/O 压力仍高，不能据此确定稳定性能或把全部耗时归因于磁盘。未重启 Docker 或 NAS。临时宿主诊断接口仅绑定 localhost，已随有界诊断进程退出。
尚未启用真实帖子筛选或修改 Discourse 审核设置，不触发更新公告发布。

## 资源扩容与公开题测试

用户授权增加 CPU、内存并进行网络测试题的功能和性能验证。本次调至 12 CPU／8 GB／12 线程。
题源、固定抽样、评分方式和限制见 [SOURCES.md](../../work/blackroom-jev/benchmark-sources/SOURCES.md)；测量记录与结论见 [功能与性能测试报告](../../work/blackroom-jev/benchmark-report.md)。
官方 [运行说明](https://github.com/feder-cr/jev/wiki/run-an-llm-locally-without-a-gpu) 明确写明 English only；不能把中文合成样本、开源 jevos 与云端 TypeSafe Jev 的测量混为一谈。

2026-10-10 完成回读：12 CPU／8 GiB／12 线程已生效，重启计数 0，内存峰值 1.57 GiB，无 OOM 与 CPU 配额节流。相同官方请求的中位耗时：short 7.983 → 3.972 秒，long 28.079 → 12.108 秒。公开 60 题初测正确 42 题；公开短信提问对照正确 14／20，仍漏报 6／10 垃圾信息。本站中文样本漏报 2／4 违规内容，未启用生产审核。
当前发布版本的 noul.criteria 不参与模型推理，规则应放在 instructions；choice／score 的 criteria 与此不同。完整对应源码与配对测试证据在报告中。

回退只涉及本服务：先停止新服务，再启动旧容器，二者使用同一接口端口，不能同时运行。

```sh
docker --context nas stop --timeout 20 blackroom-jev-nvme
docker --context nas start blackroom-jev-4cpu-3gb
```

回退后复核 `/health`。旧容器默认禁止自动重启，若决定长期保留旧配置，另行调整重启策略，并保持 Compose 配置与选择的资源版本一致。
