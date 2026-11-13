# CI/CD 从 0 基础到精通

> 一套"**文档教程为主线 + 可运行 Demo 为辅助 + 真实服务器跑通为终点**"的 CI/CD 学习体系。
> 主推平台：**Jenkins**（GitHub Actions / GitLab CI 全程横向对照）。
> 部署形态：**单机实战**（Docker + Docker Compose + Nginx + HTTPS），部署目标是一台真实的腾讯云 CVM（`yengxun-yun`，Ubuntu 26.04 实测）。
> 仓库：`git@github.com:yuxmgit/cicd-tutorial.git`（分支保护建议见第 02 章，Webhook 配置见第 05 章）。

## 一、为什么学这个？

想象一家只做外卖的小餐厅：

- 没有流水线：老板每天自己买菜、自己炒菜、自己装盘、自己骑电瓶车送餐。一天做 3 单就累趴，炒咸了也没法撤回。
- 有了流水线：收银台（Git 仓库）收到订单（代码提交），后厨中央系统（CI/CD）自动排队 → 自动炒菜（构建）→ 自动质检（测试）→ 自动装盘打包（打镜像）→ 传菜口自动送出（部署），出错自动召回（回滚）。

CI/CD 就是给软件团队装上这套中央厨房流水线。

本教程不背概念：每一章都动手，最终把一个真实的 Vue 3 + FastAPI 项目，从 `git push` 一路做到 `https://` 上线，并亲眼看到"改一行代码，3 分钟后线上生效"和"新版本炸了，一条命令回到上一版"。

## 二、环境卡（本书一切方案的前提，不是随便写的）

| 项 | 值 | 影响 |
| --- | --- | --- |
| CI 机（本地） | Windows + Docker Desktop，跑 Jenkins | CI 与生产分离；第 17 章专讲 Windows 宿主的坑（CRLF、路径、卷挂载） |
| 生产机（远端） | 腾讯云 CVM `yengxun-yun`，`49.234.202.181`，用户 `ubuntu`（sudo 免密） | 非 root 用户，脚本全程用 `sudo`，第 11 章讲"为什么不给 root" |
| 系统 | **Ubuntu 26.04 LTS**，内核 7.0，x86_64 | 全部命令按 26.04 实测，apt 系 |
| 规格 | **4 vCPU / 3.6 GiB 内存**（available 2.9 GiB），39 GiB 盘（剩 32 GiB），已有 2 GiB Swap | 够跑 Docker + 前后端 + Nginx；Jenkins 仍不上生产机 |
| 已装软件 | git、curl、wget、python 3.14、make、ufw；**Docker 与 Nginx 未安装** | 第 11 章负责安装，并配国内镜像加速 |
| 端口 | **80/443 全部空闲**，仅 22 在监听 | 可直接用标准端口 + HTTPS，不必绕 8443 |
| 域名 | 无 | HTTPS 走自签 CA 主线 + sslip.io 进阶 |
| 镜像仓库 | GitHub GHCR / Docker Hub | 公开镜像免费，服务器公网拉取 |
| 对照案例 | 另一台华为云 `huawei-yun`：宝塔面板 + 邮件服务 + FTP，`available` 仅 **14Mi**，80/443/888/8888 全被占用 | **被否决的部署机**，作为"怎么选一台合格的生产机"反面案例写进第 11 章 |

## 三、学习路线

```
第 0 部分  建立世界观        00 环境基本功 ─► 01 CI/CD 是什么 ─► 02 Git 工作流
第 1 部分  Jenkins 主线      03 装起来 ─► 04 Pipeline 语法 ─► 05 工程化 ─► 06 三平台对照
第 2 部分  构建与质量        07 前端流水线 ─► 08 后端流水线 ─► 09 质量门禁 ─► 10 镜像与制品
第 3 部分  真机部署          11 初始化服务器 ─► 12 部署演进 ─► 13 Nginx+HTTPS ─► 14 配置与持久化 ─► 15 端到端实战
第 4 部分  精通与治理        16 提速 ─► 17 治理 ─► 18 发布可观测 ─► 19 故障手册 ─► 20 演进信号
```

## 四、章节目录

| 章节 | 文件 | 内容 | 难度 | 状态 |
| --- | --- | --- | --- | --- |
| 00 | [环境与基本功](docs/00-环境与基本功.md) | 只讲后面 20 章真正用得到的 Linux/SSH 命令 | ★☆☆ | ✅ 完成 |
| 01 | [CI/CD 到底是什么](docs/01-CICD到底是什么.md) | 中央厨房比喻讲透构建/制品/环境/发布/回滚 | ★☆☆ | ✅ 完成 |
| 02 | [Git 工作流](docs/02-Git工作流.md) | 分支模型、保护分支、Conventional Commits、语义化版本 | ★☆☆ | ✅ 完成 |
| 03 | [Jenkins 落地](docs/03-Jenkins落地.md) | Docker Desktop 起 Jenkins + 内存核算表 | ★★☆ | ✅ 完成 |
| 04 | [Pipeline 语法](docs/04-Pipeline语法.md) | Declarative 全要素 + 首个可跑通流水线 | ★★☆ | ✅ 完成 |
| 05 | [Jenkins 工程化能力](docs/05-Jenkins工程化能力.md) | 凭据、参数化、Multibranch、共享库、Webhook | ★★★ | ✅ 完成 |
| 06 | [一条流水线的三种写法](docs/06-一条流水线的三种写法.md) | Jenkins / Actions / GitLab CI 逐段对照 + 选型表 | ★★☆ | ✅ 完成 |
| 07 | [前端流水线实战](docs/07-前端流水线实战.md) | npm ci、缓存、lint、测试、体积门禁 | ★★☆ | ✅ 完成 |
| 08 | [后端流水线实战](docs/08-后端流水线实战.md) | pip 缓存、pytest、SQLite 路径、优雅退出 | ★★☆ | ✅ 完成 |
| 09 | [质量与安全门禁](docs/09-质量与安全门禁.md) | 覆盖率卡点、漏洞扫描、husky 前置门禁 | ★★☆ | ✅ 完成 |
| 10 | [镜像与制品管理](docs/10-镜像与制品管理.md) | 多阶段 Dockerfile、Tag 策略、GHCR 推拉镜像 | ★★★ | ✅ 完成 |
| 11 | [服务器初始化](docs/11-服务器初始化.md) | 先探测后动手：用户/SSH/安全组/Swap/Docker/Nginx | ★★☆ | ✅ 完成 |
| 12 | [部署方式演进](docs/12-部署方式演进.md) | scp → systemd → Compose → 蓝绿 → 秒级回滚 | ★★★ | ✅ 完成 |
| 13 | [Nginx 与 HTTPS](docs/13-Nginx与HTTPS.md) | 反代、缓存、自签 CA、sslip.io 真证书 | ★★★ | ✅ 完成 |
| 14 | [配置管理与数据持久化](docs/14-配置管理与数据持久化.md) | 双环境、Secrets、SQLite 卷、备份恢复 | ★★☆ | ✅ 完成 |
| 15 | [端到端完整实战](docs/15-端到端完整实战.md) | 空仓库→上线全链路 + 两个演示场景 | ★★★ | ✅ 完成 |
| 16 | [流水线工程化与提速](docs/16-流水线工程化与提速.md) | 并行矩阵、缓存命中率、10 分钟压到 3 分钟 | ★★★ | ✅ 完成 |
| 17 | [Jenkins 生产级治理](docs/17-Jenkins生产级治理.md) | Agent 隔离、凭据治理、备份、加固、Windows 坑 | ★★★ | ✅ 完成 |
| 18 | [发布治理与可观测](docs/18-发布治理与可观测.md) | DORA 四指标、审批、审计、告警、最小监控 | ★★☆ | ✅ 完成 |
| 19 | [故障演练手册](docs/19-故障演练手册.md) | 30+ 真实故障：定位命令、根因、修复 | ★★★ | ✅ 完成 |
| 20 | [从单机到集群的演进信号](docs/20-从单机到集群的演进信号.md) | 什么时候一台 ECS 不够用（了解即可） | ★☆☆ | ✅ 完成 |
| 附A | [命令速查](docs/附录A-命令速查.md) | 全书命令按场景归档 | — | ✅ 完成 |
| 附B | [配置模板大全](docs/附录B-配置模板大全.md) | 所有配置文件一键取用 | — | ✅ 完成 |
| 附C | [面试高频题](docs/附录C-面试高频题.md) | 40 题 + 答题要点 | — | ✅ 完成 |
| 附D | [端到端部署 Runbook](docs/附录D-端到端部署Runbook.md) | Jenkins/GitHub/Git 全流程实操 + 验证场景 | — | ✅ 完成 |

## 五、目录结构

```
cicd-tutorial/
├── README.md            ← 你在这里
├── GLOSSARY.md          术语表（全书统一口径）
├── .gitattributes       强制 LF，防 Windows CRLF 事故
├── .env.example         环境变量样例（无明文密钥）
├── docs/                21 章正文 + 4 个附录 + 探测记录
├── demos/               Vue3+Vite 前端 / FastAPI+SQLite 后端
├── pipelines/           jenkins（主线）+ github + gitlab（对照）
├── deploy/              compose / nginx / systemd / Dockerfile
└── scripts/             init / deploy / rollback / healthcheck / backup / cleanup
```

## 六、怎么读这本书

- **按顺序读第 0 部分**：00~02 是地基，跳过去后面每章都会多踩三个坑。
- **每一章的动手步骤都要真的敲**：本书所有命令都来自真实环境，直接复制可执行。
- **遇到"坑与排错"小节别跳**：那是真金白银换来的。
- **第 15 章是验收**：如果你能独立走完那一章，这门课就毕业了。

## 七、进度

- [x] 规划与目录结构
- [x] 项目骨架（本文件 + GLOSSARY + .gitattributes + .env.example）
- [x] 服务器只读探测（记录见 [docs/probe](docs/probe/2026-11-11-server-probe.md)）
- [x] 第 0 部分 00~02
- [x] demos 示例项目
- [x] Jenkins 主线 03~06
- [x] 构建与质量 07~10
- [x] 真机部署 11~15（文档与脚本就绪；**真机联调待执行**，见第 15 章准备清单）
- [x] 精通与治理 16~20
- [x] 附录与全量自检（12 个 shell 脚本通过服务器端 `bash -n` + CRLF 检查）
- [ ] **真机端到端联调**：init-server → 首次部署 → 改文案生效 → 坏版本自动回滚（按第 15 章步骤 1~10 执行，输出回填文档）
