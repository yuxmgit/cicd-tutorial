# 术语表（GLOSSARY）

全书统一口径：中文（English）首次并列，此后可直接用英文缩写。按学习顺序排列。

| 术语 | 英文 | 一句话解释（餐厅版） |
| --- | --- | --- |
| 持续集成 | Continuous Integration, CI | 每次提交订单，后厨自动试做一小份并质检，坏单立即打回 |
| 持续交付 | Continuous Delivery, CD | 质检合格的菜随时可以装盘上桌，只差按一下"出餐"按钮（人工审批） |
| 持续部署 | Continuous Deployment | 连"出餐"按钮都是自动的，合格即上桌 |
| 流水线 | Pipeline | 从收到订单到出餐的一条自动传送带，分多个工位 |
| 阶段 / 工位 | Stage | 流水线上的一个环节：备菜、炒菜、质检、装盘 |
| 作业 | Job | 某个工位上的一件具体活，有自己的操作台（运行环境） |
| 步骤 | Step | 一件活里的具体动作：颠勺、加盐、装盘 |
| 运行器 | Runner / Agent | 真正干活的厨房工人及其工位 |
| 制品 | Artifact | 炒好装盘的成品菜：构建产物、压缩包、Docker 镜像 |
| 镜像 | Image | 把整道菜连同盘子、餐巾、筷子一起真空封装的标准餐盒 |
| 容器 | Container | 拆开就能上桌的餐盒，内容与封装时完全一致 |
| 镜像仓库 | Registry | 存放标准餐盒的冷库（Docker Hub、华为云 SWR、Harbor） |
| 环境 | Environment | 大堂、包间、外卖窗口：dev / staging / prod |
| 部署 | Deployment | 把新菜端上桌，替换旧菜 |
| 发布 | Release | 正式宣布"本店新品上市"，用户可见 |
| 回滚 | Rollback | 新菜被投诉，把上一版菜重新端上桌（30 秒内完成） |
| 蓝绿发布 | Blue-Green Deployment | 两套一模一样的餐桌，蓝桌营业时绿桌备菜，备好后一键换客 |
| 滚动发布 | Rolling Deployment | 10 张桌子一张一张换菜单，全程不停业 |
| 灰度 / 金丝雀 | Canary Release | 先给 5% 的客人上新菜，没投诉再全店推广 |
| 健康检查 | Health Check | 服务员每 10 秒问一次后厨"还能接单吗"，答不上来就换人 |
| 密钥管理 | Secrets Management | 后厨的保险柜：配方、银行卡只放在这，绝不贴墙上（.env 不入库） |
| 覆盖率 | Coverage | 质检员抽查了多少道工序，低于 80% 这单不准出餐 |
| 质量门禁 | Quality Gate | 出餐口的最终检查员：不达标不放行 |
| 语义化版本 | Semantic Versioning | 菜单版本 2.3.1：大改.加菜.修虫 |
| 约定式提交 | Conventional Commits | 订单备注统一格式：`feat:` 新菜、`fix:` 修口味、`docs:` 菜单更新 |
| 分支保护 | Branch Protection | 总账本（main 分支）谁都不能直接改，必须走审批 |
| Pull Request / Merge Request | PR / MR | "申请把我的新菜加进总菜单"的审批单 |
| Webhook | Webhook | 收银台一键通知后厨的传菜铃：订单一到，流水线自动启动 |
| 自托管 Runner | Self-hosted Runner | 自己招聘的厨房工人（对比外包工人：平台托管的 Runner） |
| GitOps | GitOps | 总菜单是唯一真相源：厨房状态永远向总菜单看齐，有偏差自动纠正 |
| DORA 指标 | DORA Metrics | 餐厅经营四件套：出餐频率、下单到上桌时长、翻车率、救场速度 |
| 无状态 | Stateless | 后厨不记客人的脸，全写在共享小黑板上，换人无缝接单 |
| 软链接发布 | Symlink Release | 传菜口永远指向"当前菜"：切版本只是换个标签，秒级完成 |
| 多分支流水线 | Multibranch Pipeline | 每推一个新分支，Jenkins 自动给它建一个子任务，分支删了任务跟着消失 |
| 冒烟测试 | Smoke Test | 出餐前自己先尝一口：起一个临时容器探活，通过才准进下一道工序 |
| 压缩合并 | Squash and Merge | 一个分支里的十几条零碎提交，合并进 main 时压成一条干净的记录 |
| 内网穿透 | Tunnel / Port Forwarding | 店开在巷子里没有临街门牌，找个临街铺面（frps）替你收客，再从后门把人带进店里（frpc 隧道） |
| 容器镜像服务 | GHCR / Docker Hub | GitHub 的餐盒冷库：构建好的镜像推上去，部署机随时取 |
| 凭据 | Credentials | Jenkins 的保险柜：私钥、Token 都存这里，流水线只喊编号不喊密码 |

> 新术语随章节补充；发现书里用了表外术语请先来这里查。
