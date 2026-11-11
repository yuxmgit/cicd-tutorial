# 第 05 章 Jenkins 工程化能力

> 难度：★★★　预计耗时：100 分钟
> 本章目标：让 Jenkins 从"能跑"变成"能用在团队里"——密钥不裸奔、分支自动发现、配置跟代码一起版本化、提交即触发。

---

## 一、为什么需要这一章

前两章的 Jenkins 是个玩具：脚本写在界面里、密码写在脚本里、每次新建分支都要手动建任务。真上团队，会立刻踩四个坑：

**坑 1：密钥裸奔。** 图省事在 Jenkinsfile 里写 `ssh root@1.2.3.4 -p 'MyPass123'`。这份文件进了 Git 仓库，仓库里所有人（包括离职的人克隆的副本）都能看到你的生产密码。改密码？得把所有副本追回来，做不到。

**坑 2：任务爆炸。** 一个项目有 `main`、`develop`、`feature/*` 二十多个分支。每个分支手动建一个 Jenkins 任务，改一次流水线要改二十次。

**坑 3：配置漂移。** 流水线脚本存在 Jenkins 界面里。某次 Jenkins 磁盘坏了，重装后所有流水线定义**全没了**——因为从来没进过 Git。

**坑 4：永远在轮询。** 没配 Webhook，Jenkins 每 5 分钟问一次"有新提交吗"。平均延迟 2.5 分钟，服务器还得一直被打。

> 这一章把这四个坑一次性填掉：**凭据**、**多分支流水线**、**Jenkinsfile 入库**、**Webhook 触发**。再加一个进阶武器：**共享库**，把重复的流水线逻辑抽出来复用。

---

## 二、原理图解：一次提交是怎么自动跑起来的

```mermaid
sequenceDiagram
    participant Dev as 开发者
    participant Git as 代码仓库<br/>(GitHub/GitLab/Gitea)
    participant Hook as Webhook
    participant J as Jenkins<br/>Multibranch
    participant Agent as 执行器
    participant Prod as 生产服务器

    Dev->>Git: git push feature/login
    Git->>Hook: POST /github-webhook/
    Hook->>J: 通知"有新提交"
    J->>J: 扫描到分支 feature/login<br/>读取该分支的 Jenkinsfile
    J->>Agent: 分配构建
    Agent->>Agent: 读凭据（SSH 私钥打码注入）
    Agent->>Prod: ssh + docker compose 部署
    Prod-->>Agent: 健康检查 200
    Agent-->>J: 构建成功
    J-->>Dev: 通知（邮件/企业微信）
```

四个能力分别卡在这条链的不同位置：

| 能力 | 卡在哪 | 不配会怎样 |
| --- | --- | --- |
| 凭据 | Agent → Prod 那一步 | 密码写进代码，泄露 |
| 多分支 | 扫描分支那一步 | 每个分支手动建任务 |
| Jenkinsfile 入库 | 读取流水线定义那一步 | 配置只存在于 Jenkins 里，易丢 |
| Webhook | Git → Jenkins 那一步 | 只能轮询，延迟且浪费 |

---

## 三、动手步骤

### 步骤 1 创建三类凭据（先建 SSH 私钥，后面部署要用）

**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

#### ① SSH 私钥（部署到服务器用）

| 字段 | 填什么 |
| --- | --- |
| Kind | `SSH Username with private key` |
| ID | `deploy-ssh-key`（**记住这个 ID，Jenkinsfile 里要用**） |
| Description | `腾讯云 49.234.202.181 部署私钥（ubuntu）` |
| Username | `ubuntu` |
| Private Key | 选 `Enter directly`，粘贴你的**私钥**内容 |

私钥从哪来？就是你本机 `C:\Users\yuxiangming\.ssh\id_ed25519` 的内容：

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519
```

把 `-----BEGIN OPENSSH PRIVATE KEY-----` 到 `-----END OPENSSH PRIVATE KEY-----` 全部复制进去（含首尾两行）。

> **注意**：如果私钥有 passphrase，Jenkins 的 SSH Agent 插件支持填 Passphrase；用 `ssh-keygen -p -f 私钥` 可以改。

#### ② 用户名密码（镜像仓库登录等）

| 字段 | 填什么 |
| --- | --- |
| Kind | `Username with password` |
| ID | `tcr-registry`（示例） |
| Username | 腾讯云账号或 TCR 用户名 |
| Password | 对应的密码 / Token |

#### ③ Secret text（Token、Webhook 密钥）

| 字段 | 填什么 |
| --- | --- |
| Kind | `Secret text` |
| ID | `github-webhook-token` |
| Secret | 你生成的一串随机字符 |

生成随机 Token：

```powershell
# PowerShell
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

**命名规范（团队约定，很值得抄）**：`<用途>-<对象>-<类型>`，例如 `deploy-ssh-key`、`tcr-registry`、`notify-wecom-token`。**永远不要用 `my-secret-1` 这种名字**——三个月后没人知道它是干什么的。

### 步骤 2 在流水线里安全使用凭据

`withCredentials` 支持多种绑定方式，最常用的四种：

```groovy
// ① SSH 私钥：注入一个临时文件路径到变量 SSH_KEY
withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key', keyFileVariable: 'SSH_KEY')]) {
    sh 'ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new ubuntu@49.234.202.181 "hostname"'
}

// ② 用户名密码：分别注入两个变量
withCredentials([usernamePassword(credentialsId: 'tcr-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
    sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ccr.ccs.tencentyun.com'
}

// ③ 密文：注入一个变量
withCredentials([string(credentialsId: 'github-webhook-token', variable: 'HOOK_TOKEN')]) {
    echo '拿到 Token（日志里会显示 ****）'
}

// ④ 文件：注入一个临时文件路径（适合 kubeconfig、证书）
withCredentials([file(credentialsId: 'tls-cert', variable: 'CERT_FILE')]) {
    sh 'ls -l "$CERT_FILE"'
}
```

**三条安全红线**：

1. **不要 `echo` 凭据**。Jenkins 会自动把凭据值替换成 `****`，但你自己拼出来的变形（比如 base64 后）不会被替换。
2. **不要开 `sh 'set -x'`**。调试用的 `-x` 会把命令原文（含展开后的密码）打进日志。
3. **不要写进 `environment`**。`environment` 的内容在 Blue Ocean 和环境变量页面上是明文可见的。

验证打码效果：执行 `sh 'echo "密码是 $REG_PASS"'`，日志里应该看到：

```text
密码是 ****
```

如果看到明文，说明凭据类型选错了（比如用 Secret text 当密码变量绑到了 `passwordVariable`）。

### 步骤 3 Jenkinsfile 必须入库（这是纪律）

| 做法 | 后果 |
| --- | --- |
| 脚本写在 Jenkins 界面 | 改一次要登录 Jenkins；无历史；无评审；Jenkins 挂了就没了 |
| **脚本放在仓库的 `Jenkinsfile`** | 跟代码一起评审、一起回滚、一起打 tag |

标准做法：

```groovy
// 任务配置里选：Pipeline script from SCM
// SCM: Git
// Repository URL: 你的仓库地址
// Script Path: Jenkinsfile        ← 根目录
// 或：pipelines/jenkins/Jenkinsfile  ← 想放子目录就写清楚
```

> **一个仓库多个项目怎么办**：用不同的 `Script Path`，比如 `pipelines/jenkins/Jenkinsfile-frontend`、`Jenkinsfile-backend`，各自建任务，共用同一个仓库。

### 步骤 4 多分支流水线：让分支自己长出来

**新建任务 → 选 `Multibranch Pipeline`**（不是普通 Pipeline）→ 配置：

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| Branch Sources | Git / GitHub / GitLab | 选你的仓库类型 |
| Repository URL | 仓库地址 | 私有仓库要配凭据 |
| Credentials | 选一个能读仓库的凭据 | 只读权限就够 |
| Behaviors → Discover branches | 保留 | 默认即可 |
| Property strategy | `All branches get the same properties` | 简化 |
| Build Configuration → Mode | `by Jenkinsfile` | **不要选"按 SCM 自动"** |
| Script Path | `Jenkinsfile` | 与仓库里文件名一致 |
| Scan 触发器 | 每 5 分钟（先这样，Webhook 见步骤 5） | 起步用轮询 |

保存后，Jenkins 会自动扫描并**为每个分支建一个子任务**。分支删除后，子任务自动消失（可配置保留策略）。

**在 Jenkinsfile 里按分支做不同的事**（这是多分支的价值所在）：

```groovy
pipeline {
    agent any
    stages {
        stage('测试') {
            steps { sh 'npm ci && npm test' }
        }
        stage('部署测试环境') {
            when { branch 'develop' }
            steps { sh './scripts/deploy.sh staging' }
        }
        stage('部署生产') {
            when { branch 'main' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: '确认部署生产？', ok: '部署', submitter: 'admin'
                }
                sh './scripts/deploy.sh prod'
            }
        }
    }
}
```

**验证**：推一个 `feature/test-webhook` 分支，几分钟内 Jenkins 上应该多出一个同名任务，且只跑了"测试"，没跑部署。

### 步骤 5 Webhook：让提交立刻触发

这里有个绕不过去的现实问题：**你的 Jenkins 在本地 Windows 上，GitHub/GitLab 在公网上，够不着你的 `localhost:8080`。**

三条路，按推荐顺序：

#### 路线 A：内网穿透（教学/演示最快）

用 cpolar、ngrok、frp 任选一个，把本地 8080 暴露成一个公网地址，例如 `https://abc123.cpolar.top`。

1. Jenkins 里设置 **Jenkins URL** 为这个公网地址（Manage Jenkins → System）。
2. GitHub 仓库 → Settings → Webhooks → Add webhook：
   - Payload URL：`https://abc123.cpolar.top/github-webhook/`（**结尾斜杠不能少**）
   - Content type：`application/json`
   - Secret：填你在 Jenkins 里建的 `github-webhook-token` 值
   - 事件：`Just the push event`
3. GitLab 仓库 → Settings → Webhooks：
   - URL：`https://abc123.cpolar.top/project/任务名`（GitLab 插件的路径规则不同，见下）
   - Trigger：`Push events`、`Merge request events`

> **注意安全**：穿透地址等于把你的 Jenkins 暴露给互联网。演示完立刻关掉，且不要用弱密码。

#### 路线 B：轮询（最省事，延迟可接受）

```groovy
triggers {
    pollSCM('H/5 * * * *')   // 每 5 分钟检查一次，H 会打散到不同分钟避免拥堵
}
```

延迟平均 2.5 分钟，对学习和小团队完全够用。**本书实操默认用这条**，避免为了 Webhook 去折腾穿透。

#### 路线 C：把 Jenkins 放到有公网的服务器（企业最终形态）

给 Jenkins 单独一台有公网 IP 的机器（或内网机器 + 反代），这才是生产做法。第 17 章会讲"CI 机到底应该放哪"。

**GitHub 与 GitLab 的 URL 差别（易错点）**：

| 平台 | Webhook 路径 |
| --- | --- |
| GitHub | `/github-webhook/` |
| GitHub（多分支） | 同上，插件自动处理 |
| GitLab | `/project/<任务名>`（项目级）或 `/gitlab-webhook/post`（插件新版） |
| Gitea | `/gitea-webhook/post` |

配完点 "Test / Redeliver"，Jenkins 上应该立刻出现一次构建。**如果没有，先看 Jenkins 系统日志（Manage Jenkins → System Log）里有没有收到请求**——没收到就是网络问题，收到了没触发就是路径或 Token 问题。

### 步骤 6 共享库：把重复逻辑抽出来（进阶但值得）

当你有 5 个项目，每个 Jenkinsfile 都有 30 行相同的 `docker build + push + ssh 部署`，就到了抽共享库的时候。

**目录结构**（本项目的 `pipelines/jenkins/shared-library/` 就是现成模板）：

```text
shared-library/
├── vars/                    全局函数（在 Jenkinsfile 里直接调用）
│   ├── buildImage.groovy
│   └── deployToServer.groovy
├── src/                     普通 Groovy 类（按包名 import）
└── resources/               静态资源（脚本、模板）
```

`vars/buildImage.groovy`：

```groovy
def call(Map cfg = [:]) {
    def registry  = cfg.registry  ?: 'ccr.ccs.tencentyun.com'
    def namespace = cfg.namespace ?: 'default'
    def name      = cfg.name      ?: error('缺少 name 参数')
    def tag       = cfg.tag       ?: "${env.BUILD_NUMBER}"
    def dockerfile= cfg.dockerfile?: 'Dockerfile'
    def context   = cfg.context   ?: '.'

    def image = "${registry}/${namespace}/${name}:${tag}"
    echo "准备构建镜像：${image}"

    retry(2) {
        sh "docker build -t ${image} -f ${dockerfile} ${context}"
    }

    withCredentials([usernamePassword(
        credentialsId: cfg.registryCredentialId ?: 'tcr-registry',
        usernameVariable: 'REG_USER',
        passwordVariable: 'REG_PASS'
    )]) {
        sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ' + registry
        sh "docker push ${image}"
    }
    return image
}
```

`vars/deployToServer.groovy`：

```groovy
def call(Map cfg = [:]) {
    def host  = cfg.host  ?: error('缺少 host 参数')
    def user  = cfg.user  ?: 'ubuntu'
    def dir   = cfg.dir   ?: '/opt/apps/cicd-demo'
    def tag   = cfg.tag   ?: error('缺少 tag 参数')
    def credId= cfg.credentialsId ?: 'deploy-ssh-key'

    withCredentials([sshUserPrivateKey(credentialsId: credId, keyFileVariable: 'SSH_KEY')]) {
        sh """
            ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new ${user}@${host} \
              'cd ${dir} && ./scripts/deploy.sh ${tag}'
        """
    }
}
```

**在 Jenkins 里注册共享库**：Manage Jenkins → System → Global Pipeline Libraries：

| 字段 | 值 |
| --- | --- |
| Name | `cicd-lib` |
| Default version | `main` |
| Retrieval method | Modern SCM → Git → 你的仓库地址 |
| Library Path | `pipelines/jenkins/shared-library` |

**在 Jenkinsfile 里使用**：

```groovy
@Library('cicd-lib@main') _

pipeline {
    agent any
    stages {
        stage('构建镜像') {
            steps {
                script {
                    def image = buildImage(name: 'cicd-demo-backend', tag: env.BUILD_NUMBER,
                                           dockerfile: 'deploy/Dockerfile.backend', context: 'demos/backend')
                    deployToServer(host: '49.234.202.181', tag: env.BUILD_NUMBER)
                }
            }
        }
    }
}
```

**两个坑**：

1. `@Library` 必须放在文件**第一行**（注释除外），下面的 `_` 是必须的占位符语法。
2. 共享库里的 `sh` 里用 Groovy 变量要用 `"..."` 双引号；要保留 shell 变量（如 `$SSH_KEY`）必须写 `\$SSH_KEY` 转义，否则 Groovy 会先吃掉它。

---

## 四、完整实例：从 push 到自动构建的全流程

假设：仓库在 GitHub（私有），Jenkins 在本地，用轮询触发。

**① 仓库里放 `Jenkinsfile`（根目录）**

```groovy
pipeline {
    agent any
    options {
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }
    triggers {
        pollSCM('H/5 * * * *')
    }
    stages {
        stage('检出') {
            steps { checkout scm; sh 'git log -1 --oneline' }
        }
        stage('测试') {
            steps {
                dir('demos/backend') {
                    sh 'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt'
                    sh '.venv/bin/pytest'
                }
            }
        }
        stage('部署（仅 main）') {
            when { branch 'main' }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key', keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new ubuntu@49.234.202.181 \
                          'echo "生产机连接成功：$(hostname)"'
                    '''
                }
            }
        }
    }
    post {
        failure { echo "失败：${env.BUILD_URL}console" }
        cleanup { cleanWs() }
    }
}
```

**② Jenkins 建 Multibranch Pipeline，指向这个仓库，Script Path 填 `Jenkinsfile`**

**③ 推送一个分支**

```powershell
git switch -c feature/jenkins-test
git commit --allow-empty -m "ci: 测试多分支流水线"
git push -u origin feature/jenkins-test
```

**④ 观察**

- 5 分钟内，Jenkins 首页出现 `feature/jenkins-test` 子任务
- 它自动执行了"检出 + 测试"，**跳过**了"部署"（因为不是 main）
- 合并到 main 后，`main` 分支的任务会执行部署阶段

**验证成功的标准**：

- 分支自动出现、自动消失
- Jenkinsfile 改动提交后，流水线行为跟着变（不需要在界面上改任何东西）
- 日志里凭据显示 `****`
- `feature` 分支不会部署生产

---

## 五、坑与排错

| 现象 | 根因 | 解法 |
| --- | --- | --- |
| Webhook 显示 404 | URL 少了结尾斜杠，或路径不对 | GitHub 用 `/github-webhook/`；看 Jenkins 系统日志 |
| Webhook 显示超时/连不上 | Jenkins 在内网，公网够不着 | 用穿透、或改轮询、或把 Jenkins 放公网机 |
| Multibranch 扫不到分支 | 仓库凭据无读权限，或过滤规则排除 | 检查凭据；看 Scan 日志 |
| Jenkinsfile 改了不生效 | 任务用的是"界面脚本"而非 SCM | 任务配置里改成 Pipeline script from SCM |
| `@Library` 报 `No such library` | 名字拼错 / 版本不对 / 路径配错 | 核对 Global Pipeline Libraries 的 Name 与 Library Path |
| 共享库函数报 `MissingPropertyException` | `vars/` 文件名与函数名不一致 | `vars/buildImage.groovy` 里必须是 `def call(...)` |
| 凭据日志变明文 | 用了 `echo` + 字符串拼接/编码 | 改用 `withCredentials` 原生绑定，别二次加工 |
| `docker: command not found` | Jenkins 容器里没装 Docker CLI | 第 10 章会做专用镜像 |
| 部署时 `Permission denied (publickey)` | 私钥与服务器 `authorized_keys` 不匹配 | 用同一个私钥在本地先验证 `ssh -i` |

---

## 六、横向对照：凭据与触发

| 能力 | Jenkins | GitHub Actions | GitLab CI |
| --- | --- | --- | --- |
| 存密钥 | Credentials（ID 引用） | Repository secrets | CI/CD Variables（可设 File/Masked） |
| 使用方式 | `withCredentials([...])` | `${{ secrets.NAME }}` | `$NAME` |
| 日志打码 | 自动 | 自动 | 勾选 Masked 才打码（**易漏**） |
| 触发方式 | Webhook / pollSCM | `on: push` | Webhook（自动） |
| 分支过滤 | Multibranch + `when { branch }` | `on: push: branches:` | `rules: if: $CI_COMMIT_BRANCH` |
| 可复用逻辑 | 共享库 | Reusable workflow / Composite Action | `include:` + `extends:` |
| 环境级保护 | `input` + 角色权限 | Environments + Required reviewers | Protected environments |

---

## 七、本章检查清单与练习

### 检查清单

- [ ] 建好了 `deploy-ssh-key` 凭据，并能在流水线里 `ssh` 成功
- [ ] 日志里凭据显示为 `****`
- [ ] 建了 Multibranch 任务，新推分支 5 分钟内自动出现
- [ ] `Jenkinsfile` 在仓库里，改它能让流水线行为变化
- [ ] 配了轮询或 Webhook，提交后自动触发
- [ ] 知道共享库的 `vars/`、`src/`、`resources/` 分别放什么

### 练习

**练习 1**：公司要求"只有运维组能部署生产，开发只能部署测试"，用 Jenkins 原生能力怎么实现（不写代码）？
<details><summary>参考要点</summary>

① 用 Role-based Authorization Strategy 插件建 `ops` 角色，给 Job/Build 权限；② 部署 stage 加 `input submitter: 'ops-team'`；③ 更严格：把部署任务放在只允许 ops 访问的 Folder 里。
</details>

**练习 2**：共享库函数里写了 `sh "ssh -i $SSH_KEY ..."`，执行时报 `-i: command not found` 或变量为空，为什么？
<details><summary>参考要点</summary>

Groovy 双引号会先插值，`$SSH_KEY` 被 Groovy 当成未定义变量替换成空。要保留给 shell：写 `\$SSH_KEY`，或改用单引号字符串拼接。
</details>

**练习 3**：为什么"每个分支手动建一个 Jenkins 任务"在团队里一定会失控？举两个具体后果。
<details><summary>参考要点</summary>

① 分支多时任务数量爆炸，改流水线要改 N 次，必然出现配置漂移；② 删除分支后任务残留，指向不存在的分支，天天报红，团队逐渐无视报警（狼来了）。
</details>

---

## 下一章预告

Jenkins 这套已经能用了。第 06 章把同一件事用 GitHub Actions 和 GitLab CI 各写一遍，逐段对照，并给出一张能直接拿去开会用的平台选型决策表。
