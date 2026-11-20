# 附录 E Jenkins 凭据详解

> 用途：把实操环境里 4 条凭据逐一讲透——**它是什么、为什么必须存在、底层原理、怎么创建、流水线里怎么用、坏了怎么排错**。
> 配合附录 D（端到端 Runbook）使用：D 告诉你"填什么"，E 告诉你"为什么这么填"。
> 前置知识：第 3 章（Jenkins 落地）、第 5 章（凭据与 Multibranch）、第 10 章（GHCR）、第 11 章（服务器 SSH）。

---

## 0. 总览：4 条凭据各管一段旅程

一条代码从提交到上线，会经过 4 个"需要验明正身"的关口，每条凭据守一个：

```
开发者 push ──► ③ Webhook 通知 Jenkins ──► ② Jenkins 拉代码 ──► 测试/构建镜像
                   （github-webhook-token）    （github-repo-readonly）      │
                                                                            ▼
              ① Jenkins ssh 部署 ◄────────────────────────── ④ docker login 推镜像
              （deploy-ssh-key）                             （ghcr-registry）
```

| ID | 类型 | 守护的关口 | 对端是谁 |
| --- | --- | --- | --- |
| `deploy-ssh-key` | SSH Username with private key | Jenkins → 生产机部署 | Linux 服务器 `ubuntu` 用户 |
| `ghcr-registry` | Username with password | Jenkins → GHCR 推镜像 | GitHub 容器仓库 |
| `github-repo-readonly` | Username with password | Jenkins → GitHub 拉代码 | GitHub 仓库 + API |
| `github-webhook-token` | Secret text | GitHub → Jenkins 触发构建 | 对称密钥（双方共享） |

> **为什么凭据 ID 不能随便改名**：Jenkinsfile 里写的是 `credentialsId: 'ghcr-registry'`，Multibranch 配置里选的也是这个名字。ID 是凭据的"主键"，改名等于流水线失忆。同理，附录 D 里写的 `github-repo-readonly` 和界面上建的 `github-repo-read-only` 差一个横杠都会报"找不到凭据"——两边必须逐字符一致。

---

## 1. `deploy-ssh-key` —— Jenkins 部署时的"通行证"

### 1.1 它是什么

一对 SSH 密钥中的**私钥**，加上持有者用户名 `ubuntu`。Jenkins 用它发起 `ssh ubuntu@49.234.202.181` 并执行部署脚本，全程不需要密码。

### 1.2 为什么需要它

流水线的最后一个 stage（⑥ 部署生产）必须在生产机上执行 `deploy.sh`。有三种选择，只有 SSH 密钥是对的：

| 方案 | 问题 |
| --- | --- |
| 密码认证 | 密码明文进凭据库 + 服务器要开密码登录（暴露面大） |
| 把私钥存进 Jenkinsfile | 私钥进了 git 历史，全员可见，等于裸奔 |
| **SSH 密钥 + Jenkins 凭据** | 私钥加密存储、日志自动掩码、可随时吊销换新 ✅ |

### 1.3 原理：非对称加密的"单向信任"

```
Jenkins（持私钥）                          生产机（持公钥，写在 ~/.ssh/authorized_keys）
     │ 1. 请求连接，出示用私钥签名的挑战值 ──►│
     │◄── 2. 用公钥验签，通过即放行           │
```

- 服务器只存公钥（泄露无所谓），Jenkins 存私钥（这是唯一需要保护的半个）
- 服务器管理员随时删掉 `authorized_keys` 里那一行 = 吊销 Jenkins 的部署权限
- 与"密码"的本质区别：密码每次连接都要发送（可被截获），密钥认证中私钥**永不离开 Jenkins**

### 1.4 创建流程

```bash
# 在任意一台机器上生成专用密钥对（-f 指定文件名，别覆盖自己的默认密钥）
ssh-keygen -t ed25519 -f deploy_key -C "jenkins-deploy" -N ""
```

然后两半各去各的地方：

```bash
# 公钥 → 生产机（追加进 authorized_keys）
ssh-copy-id -i deploy_key.pub ubuntu@49.234.202.181
# 等价于手工：把 deploy_key.pub 内容追加到服务器 ~/.ssh/authorized_keys

# 本机先验证密钥对本身是通的（能免密登录才继续）
ssh -i deploy_key ubuntu@49.234.202.181 'echo ok'
```

Jenkins 侧：Manage Jenkins → Credentials → Add Credentials
- Kind：**SSH Username with private key**
- ID：`deploy-ssh-key`
- Username：`ubuntu`（会传给流水线里的 `${DEPLOY_HOST}` 拼接使用）
- Private Key：选 **Enter directly**，把 `deploy_key`（**没有 .pub 的那个文件**）全文粘进去，包括 `-----BEGIN` 和 `-----END` 两行

> 最常见的翻车：把 `.pub` 公钥贴进了 Jenkins。私钥长这样（开头 BEGIN OPENSSH PRIVATE KEY），公钥是一行 `ssh-ed25519 AAAA...` 开头。贴错了 Stage ⑥ 会报 `Permission denied (publickey)`。

### 1.5 流水线里怎么用

```groovy
withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key',
                                   keyFileVariable: 'SSH_KEY')]) {
    sh 'ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new ubuntu@49.234.202.181 ...'
}
```

- `keyFileVariable`：Jenkins 把私钥解密后写到 agent 临时目录的一个文件里，路径放进 `SSH_KEY` 变量——`ssh -i` 需要的是文件路径，不是密钥内容
- `-o StrictHostKeyChecking=accept-new`：首次连接自动接受服务器指纹，否则卡在交互式 yes/no（流水线里没有人工输入）
- 构建日志里 `SSH_KEY` 的**路径**会显示，但密钥内容不会出现；构建结束临时文件自动删除

### 1.6 坑与排错

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| `Permission denied (publickey)` | 私钥贴错（贴成公钥）/ 服务器 `authorized_keys` 没配 / 属主权限不对 | 先用本机 `ssh -i deploy_key` 复现；服务器执行 `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| `PEM format invalid` / 解析失败 | 复制时把换行弄丢了（Windows 记事本 CRLF） | 用 VS Code 复制全文；确有 CRLF 问题就在 Jenkins 里重新 Enter directly 粘贴 |
| 卡住无输出 | 首次连接在等 yes/no 确认 | 加 `-o StrictHostKeyChecking=accept-new` |
| `sudo: a password is required` | 服务器 `ubuntu` 用户 sudo 免密没配 | 按 11 章给 `ubuntu` 配 NOPASSWD（部署脚本里全是 sudo 命令） |

### 1.7 安全要点

- **专用密钥**：只用于 Jenkins 部署，不与个人日常密钥混用——泄露时吊销它不影响你自己登录
- **最小权限**：理想状态是给 Jenkins 单独建一个受限用户（只能跑 `/opt/apps/cicd-demo/scripts/` 下脚本），第 17 章的进阶做法
- **可轮换**：换密钥 = 生成新对 → 新公钥追加进 authorized_keys → Jenkins 凭据更新私钥 → 删旧公钥，流水线零停机切换

---

## 2. `ghcr-registry` —— 推镜像到 GHCR 的"发布许可"

### 2.1 它是什么

一组「GitHub 用户名 + Personal Access Token（PAT）」，PAT 必须带 **`write:packages`** 权限。专门给 `docker login ghcr.io` 用。

### 2.2 为什么需要它

流水线 ⑤ 推送镜像要执行 `docker push ghcr.io/<用户名>/cicd-demo-backend:tag`。GHCR 是 GitHub 的容器仓库，push 是**写操作**，必须先 `docker login` 证明"你有权往这个命名空间写"。没有这一步，服务器会报 `denied` 或 401。

> **命名空间就是 GitHub 用户名**：`ghcr.io/yxm1989614/cicd-demo-backend` 中间的 `yxm1989614` 决定了"哪个账号有权写它"。所以凭据里的用户名必须和镜像路径的命名空间一致——这就是"docker login 用 yarn98654 却推 yxm1989614 的镜像会 denied"的根因。

### 2.3 原理：PAT 是"替代密码的受限身份"

GitHub 不允许脚本用你的登录密码（并且账号开了 2FA 后密码根本登录不了 API），PAT 是专门为程序化访问设计的令牌：

- **可细分权限**：`write:packages` 只开放包读写，你的代码仓库、账号设置完全碰不到
- **可随时吊销**：泄露后到 GitHub 设置里删掉这个 token 即可，不用改账号密码
- **可设有效期**：过期自动失效，强制定期轮换（这是双刃剑：过期了流水线会突然 401，日志特征是 `unauthorized: authentication required`）
- docker login 收到这组用户名+令牌后，把它作为 HTTP Basic Auth 存进 registry 的会话凭证；之后每次 push/pull 请求都带上它

### 2.4 创建流程

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → Generate new token (classic)
2. Note：`ghcr-push`（方便日后辨认这是 Jenkins 用的）
3. Expiration：按需选（90 days / no expiration，教学环境选后者省心，生产建议有限期）
4. **勾选 `write:packages`**（自动带上 `read:packages`；不需要 `repo`）
5. Generate 后立刻复制（`ghp_` 开头，**只显示这一次**）

Jenkins 侧：Add Credentials
- Kind：**Username with password**
- Username：GitHub 用户名（全小写，与 GHCR 命名空间一致）
- Password：粘贴 PAT（⚠️ 不是 GitHub 登录密码）
- ID：`ghcr-registry`

**服务器也要登录一次**（拉镜像方）：部署脚本在服务器上 `docker pull`，服务器同样需要登录：

```bash
ssh ubuntu@49.234.202.181
docker login ghcr.io   # 输入同一组用户名 + PAT
```

> 服务器上登录凭证存在 `~/.docker/config.json`。如果不希望长期留在磁盘上，可改用 deploy.sh 里注入 `REG_PASS` 的方式 `--password-stdin` 登录（第 10 章的进阶写法）。

### 2.5 流水线里怎么用

```groovy
withCredentials([usernamePassword(credentialsId: 'ghcr-registry',
                                  usernameVariable: 'REG_USER',
                                  passwordVariable: 'REG_PASS')]) {
    sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ghcr.io'
    sh "docker push ${IMAGE_BACKEND}"
}
```

- `--password-stdin`：密码从管道进，**不出现在命令行**（直接 `-p` 传密码会被 `ps` 和 shell 历史记录看到）
- 日志掩码：`echo "$REG_PASS"` 的输出在 Jenkins 日志里显示为 `****`，这就是 withCredentials 的自动脱敏

### 2.6 坑与排错

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| `denied` / `unauthorized` | PAT 没勾 `write:packages`；或用户名与命名空间不一致；或 token 过期 | 逐项核对；重开 401 时先怀疑过期 |
| `name unknown` / `manifest unknown` | 推送路径的命名空间不存在或拼错 | 检查 `NAMESPACE` 变量是否等于 GitHub 用户名（全小写） |
| 服务器拉镜像 401 | 服务器没 `docker login`（它和 Jenkins 是两台机器，凭证不共享） | 在服务器上单独登录一次 |
| token 泄露恐慌 | —— | GitHub → Developer settings 删掉该 token → 生成新 PAT → 更新 Jenkins 凭据 → 服务器重新 login |

### 2.7 安全要点

- 这个 PAT 权限比 `github-repo-readonly` **大**（能写包），所以更要分开：万一泄漏，至少代码仓库只读那条是安全的
- fine-grained token 也可以只给某一个包的权限，比 classic 更收敛，进阶可用

---

## 3. `github-repo-readonly` —— Jenkins 拉代码的"读者卡"

### 3.1 它是什么

又一组「GitHub 用户名 + PAT」，但只需**只读**权限。专门给 Multibranch 扫描分支和 checkout 用。

### 3.2 为什么需要它

Multibranch Pipeline 每次扫描要做两件事，都要认证：

1. 调 `https://api.github.com` 列出仓库的分支和 PR（决定 Jenkins 里出现哪些"子任务"）
2. `git fetch` 把代码拉到工作区

私有仓库没有凭证什么都干不了；即便是公开仓库，带凭证还能提升 API 速率限制（匿名 60 次/小时，带 token 5000 次/小时）。

### 3.3 原理：只读够了，就不要多给

这个凭据在生产链路里**只读代码**，不写任何东西，所以权限收敛到最小：

| Token 形态 | 权限配置 | 说明 |
| --- | --- | --- |
| classic | 勾 `repo` | `repo` 是个"大权限"，含读写私有仓库——够用但偏大 |
| classic | 只勾 `repo:status` + `public_repo` | 公开仓库时更收敛 |
| **fine-grained（推荐）** | Repository access 限定本仓库；Permissions → Contents: **Read-only** | 精确到"只能读这一个仓库的内容"，最安全 |

> **那个 403 的来历**：构建结尾报 `Could not update commit status: Resource not accessible by personal access token`——Jenkins 尝试把构建状态回写到 GitHub 的 commit 上（PR 页面那个绿勾/红叉），这需要 `repo:status` 权限，只读 Contents 的 token 没有它。这个报错**不影响构建本身**；想要 PR 上显示构建状态，就给 classic token 补勾 `repo:status`，或忽略它。

### 3.4 创建流程与填写

GitHub 侧（fine-grained 推荐）：
1. Settings → Developer settings → **Fine-grained tokens** → Generate new token
2. Repository access → Only select repositories → 选 `cicd-tutorial`
3. Permissions → Repository permissions → **Contents: Read-only**
4. 生成并复制

Jenkins 侧：Add Credentials
- Kind：**Username with password**
- Username：GitHub 用户名
- Password：粘贴只读 PAT
- ID：`github-repo-readonly`（与 Multibranch 配置里选的名字逐字符一致）

两处引用点（都要对上）：
- Multibranch → Configure → Branch Sources → GitHub → Credentials 下拉选中它
- （如有）流水线里显式 `checkout scmGit(credentialsId: 'github-repo-readonly', ...)`

### 3.5 坑与排错

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| `Failed to connect ... port 443` | **不是凭据问题**，是网络到 GitHub 不通（国内环境间歇性断流） | 重试构建；根治靠代理。区分方法：报错在 connect 阶段 = 网络；在认证阶段 = 凭据 |
| `Authentication failed` / 401 | token 过期或删除 | 重新生成，更新凭据 |
| `Not Found` (404) | token 没有该仓库权限（fine-grained 忘了选仓库） | 重新配置 Repository access |
| commit status 403 | 缺 `repo:status` 权限 | 补权限或忽略（见 3.3） |
| 扫描频繁触发 API 限流 | 分支太多 + 匿名/失效 token | 确认凭据有效；调大扫描间隔 |

### 3.6 安全要点

- 与 `ghcr-registry` 分开成两个 token：**权限最小化 + 可独立吊销**，这是"一凭据一职责"原则
- 它只读，就算整个 Jenkins 被攻破，攻击者拿到的也只是"读代码"，写不了包、改不了服务器

---

## 4. `github-webhook-token` —— 识别"真 push 通知"的暗号

### 4.1 它是什么

一段任意的随机字符串（Secret text 类型），**同时配置在 GitHub Webhook 和 Jenkins 里**，用于校验"这条 push 通知真的是 GitHub 发的"。

### 4.2 为什么需要它

Webhook 的触发地址 `http://49.234.202.181:18080/github-webhook/` 是公网可达的。如果不校验，任何人 curl 一下这个地址就能伪造 push 事件，让 Jenkins 疯狂空跑构建（资源攻击）。Webhook Secret 让 Jenkins 只接受"用同一暗号签过名"的通知。

### 4.3 原理：HMAC-SHA256 对称签名

```
GitHub 发通知时：payload + Secret ──HMAC-SHA256──► 签名，放在请求头
                  X-Hub-Signature-256: sha256=abcdef1234...

Jenkins 收到时：收到的 payload + 自己存的同一个 Secret ──HMAC-SHA256──► 算出签名
                与请求头里的签名逐字节比对，一致才触发构建
```

关键性质：
- **同一个 Secret** 两边各存一份（对称），GitHub 用来"签"，Jenkins 用来"验"
- 中间人改了 payload（比如把分支名改成 main），签名就对不上，直接拒绝
- 攻击者不知道 Secret 就伪造不出合法签名——这就是它防的东西
- 与前三个凭据的本质区别：前三个是"我去访问别人时的身份证"，这个是"别人来找我校验时的暗号"，**不参与任何登录**

### 4.4 创建流程

生成一个足够随机的串（别用 `123456`）：

```powershell
# PowerShell
-join ((48..57)+(97..122) | Get-Random -Count 32 | % {[char]$_})
```

然后**同一串值填两处**：

1. **GitHub 侧**：仓库 → Settings → Webhooks → Add webhook → Secret 字段粘贴
   - Payload URL：`http://49.234.202.181:18080/github-webhook/`（结尾斜杠不能少）
   - Content type：`application/json`；事件：`Just the push event`
2. **Jenkins 侧**：Add Credentials
   - Kind：**Secret text**
   - Secret：粘贴同一串值
   - ID：`github-webhook-token`

Jenkins 的 GitHub 插件在 Multibranch 的 GitHub 项目配置里读到这个凭据后，对每条 webhook 做验签。

### 4.5 验证

改一行代码 push 到任意分支，然后：

- GitHub 仓库 → Settings → Webhooks → 点进这条 webhook → **Recent Deliveries**：应有 `ping`（创建时自动发）和 `push` 事件，Response **200**
- Jenkins 对应分支自动出现新构建

### 4.6 坑与排错

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| Recent Deliveries 里 Response 非 200 | Secret 两边不一致 / URL 少斜杠 / frp 没通 | 先看 Delivery 的响应体；三处逐一核对 |
| push 了但没触发 | GitHub→Jenkins 入方向断（frpc 没跑、安全组拦 18080） | 本机流量访问 `http://49.234.202.181:18080` 看能否打开登录页 |
| 200 但没构建 | Jenkins 侧凭据 ID 没挂上 / 分支被 `when` 过滤 | 看 Jenkins 系统日志（Manage Jenkins → System Log） |
| **签名校验失败被拒绝** | 两边 Secret 不一致 | 重新粘贴同一串值（最常见：一边多了空格） |

### 4.7 安全要点

- 长度 ≥ 32、真随机——它的唯一强度来源就是"猜不出来"
- 走 `http` 明文传输 payload（签名头也在里面，但 Secret 本身不在网络上传输，HMAC 的安全性不受明文影响）；上了 HTTPS 后整体更稳（第 13 章思路同理）

---

## 5. 横向对比：三种凭据类型一张表

| | SSH Username with private key | Username with password | Secret text |
| --- | --- | --- | --- |
| 本质 | 非对称私钥 | 用户名+令牌（HTTP Basic Auth） | 对称共享密钥 |
| 谁持有 | 只有我方 | 用户名公开、令牌保密 | **双方各存一份** |
| 数学基础 | 公钥验签 | ——（就是密码的替身） | HMAC-SHA256 |
| 典型场景 | ssh / scp 部署 | registry、git、API 登录 | Webhook 签名校验 |
| 吊销方式 | 服务器删公钥行 | GitHub 删 token | 两边同步换新值 |
| 泄露影响面 | 能登录对应服务器 | 能做 token 权限内的所有事 | 能伪造 webhook（但不泄露任何数据） |

**记法**：
- 「我主动去找别人」→ 身份证类（SSH key / username+password）
- 「别人来找我要验货」→ 暗号类（secret text）

---

## 6. 凭据存储与安全的底层机制（深入理解用）

1. **存储位置**：全部在 `$JENKINS_HOME/secrets/` + `credentials.xml`。Secret 用 Jenkins 主密钥（`secrets/jenkins.model.Jenkins.crpt` 派生）AES 加密后才落盘
2. **主密钥的保护**：`$JENKINS_HOME` 挂载成卷（`jenkins-home`）——所以备份 Jenkins = 备份这个卷，丢卷 = 丢全部凭据
3. **注入方式**：流水线里**永远**通过 `withCredentials(...)` 注入环境变量，绝不写明文、绝不 `echo` 后以为没人看见（withCredentials 会掩码，裸写不会）
4. **日志脱敏**：withCredentials 作用域内，变量的**值**在日志里自动替换为 `****`（但变量名不隐藏，所以 ID 可以放心写进日志）
5. **一次赋值，作用域最小**：把 withCredentials 包在需要的 stage 里，而不是整个 pipeline——作用域越小，被意外打印/传播的窗口越小
6. **轮换节奏**：PAT 设有效期即自动强制轮换；SSH key 和 webhook secret 没有有效期，要靠制度（如每季度换一次）

---

## 7. 自检清单（能答上来才算懂）

- [ ] 为什么 `ghcr-registry` 和 `github-repo-readonly` 是两个独立 token，而不是共用一个全权限 token？
- [ ] `deploy-ssh-key` 贴到 Jenkins 里的应该是哪个文件？贴错了会报什么错？
- [ ] Webhook secret 在网络传输中出现吗？它防的是"窃听"还是"伪造"？
- [ ] 构建日志结尾的 commit status 403 影响部署吗？想修好该加什么权限？
- [ ] `docker login -p "$REG_PASS"` 和 `--password-stdin` 的区别是什么？为什么教程强制后者？
- [ ] Jenkins 容器重建后凭据还在，靠的是什么？（答：`jenkins-home` 卷里的加密 secret 文件，不是容器本身）

> 答案都能在前文找到；答不上来就回到对应小节重读一遍。
