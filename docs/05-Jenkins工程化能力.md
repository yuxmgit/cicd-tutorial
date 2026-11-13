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

私钥从哪来？就是你本机 `%USERPROFILE%\.ssh\id_ed25519`（`$env:USERPROFILE\.ssh\id_ed25519`）的内容：

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519
```

把 `-----BEGIN OPENSSH PRIVATE KEY-----` 到 `-----END OPENSSH PRIVATE KEY-----` 全部复制进去（含首尾两行）。

> **注意**：如果私钥有 passphrase，Jenkins 的 SSH Agent 插件支持填 Passphrase；用 `ssh-keygen -p -f 私钥` 可以改。

#### ② 用户名密码（镜像仓库登录等）

| 字段 | 填什么 |
| --- | --- |
| Kind | `Username with password` |
| ID | `ghcr-registry`（示例） |
| Username | GitHub 用户名 |
| Password | PAT（勾选 `write:packages` / `read:packages`） |

#### ③ Secret text（Token、Webhook 密钥）

| 字段 | 填什么 |
| --- | --- |
| Kind | `Secret text` |
| ID | `github-webhook-token` |
| Secret | 你生成的一串随机字符 |

#### ④ GitHub 仓库读取凭据（私有仓库的 Multibranch 任务要用）

| 字段 | 填什么 |
| --- | --- |
| Kind | `Username with password` |
| ID | `github-repo-readonly` |
| Username | 你的 GitHub 用户名 |
| Password | Personal Access Token（classic 勾 `repo`；fine-grained 只给 `Contents: Read-only` 即可） |

三个易混点：

1. **不是账号密码**。GitHub 早已禁用密码认证，Password 必须填 PAT，否则报 `Authentication failed`。
2. **和 ② 不是一回事**。`ghcr-registry` 是给 `docker login` 镜像仓库的，这条是给"拉代码"用的，别想着共用一个。
3. **和 ① 也不冲突**。① 的 SSH 私钥是"部署到服务器"，这条是"从 GitHub 读代码"；服务器上的 `authorized_keys` 和 GitHub 上的公钥两套东西。

生成随机 Token：

```powershell
# PowerShell
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

**命名规范（团队约定，很值得抄）**：`<用途>-<对象>-<类型>`，例如 `deploy-ssh-key`、`ghcr-registry`、`github-repo-readonly`、`notify-wecom-token`。**永远不要用 `my-secret-1` 这种名字**——三个月后没人知道它是干什么的。

### 步骤 2 在流水线里安全使用凭据

`withCredentials` 支持多种绑定方式，最常用的四种：

```groovy
// ① SSH 私钥：注入一个临时文件路径到变量 SSH_KEY
withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key', keyFileVariable: 'SSH_KEY')]) {
    sh 'ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new ubuntu@49.234.202.181 "hostname"'
}

// ② 用户名密码：分别注入两个变量
withCredentials([usernamePassword(credentialsId: 'ghcr-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
    sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ghcr.io'
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

#### 路线 A：自建 frp（推荐，公网地址永久不变）

先说结论：**cpolar、ngrok、natapp 的免费版每次重启都换域名**，Webhook 得跟着改一遍，只能演示、不能日常用。要"填一次永远不变"，最省事的做法是用已有的云服务器自建 frp——公网地址固定为 `http://49.234.202.181:18080`，本机重启也不变。

**先理解方向，后面就不会绕晕**：不是服务器连你，而是你本机的 `frpc` **主动出站**连到服务器的 `frps`，把本机 8080 注册到服务器的 18080 上：

```text
GitHub ──► 49.234.202.181:18080（frps 公网入口）
                    │  复用已建立的隧道
                    ▼
           127.0.0.1:8080（本机 Win11 上的 Jenkins，完全不用改）
```

好处：不需要公网 IP、不用改路由器端口映射、Jenkins 依然在本机 `localhost:8080`。

**① 服务端（腾讯云 49.234.202.181）**

```bash
# 下载（国内服务器直连 GitHub 极慢，用加速前缀；版本号以 Releases 最新为准）
cd /opt
VER=0.72.0
sudo wget -O frp.tar.gz "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v${VER}/frp_${VER}_linux_amd64.tar.gz"
gzip -t frp.tar.gz && echo "压缩包完好"     # 必须先校验，见排错表里的 EOF 坑
sudo tar -zxf frp.tar.gz && sudo mv frp_${VER}_linux_amd64 frp

# 生成 token，复制下来，客户端要用同一串
tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; echo

sudo tee /opt/frp/frps.toml <<'EOF'
bindPort = 7000
auth.method = "token"
auth.token = "把上行生成的32位随机串粘这里"
webServer.addr = "127.0.0.1"
webServer.port = 7500
EOF

# 前台试跑，看到 frps started successfully 就 Ctrl+C
sudo /opt/frp/frps -c /opt/frp/frps.toml
```

注册为系统服务（开机自启）：

```bash
sudo tee /etc/systemd/system/frps.service <<'EOF'
[Unit]
Description=frp server
After=network.target

[Service]
Type=simple
ExecStart=/opt/frp/frps -c /opt/frp/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && sudo systemctl enable --now frps
sudo systemctl status frps --no-pager
```

**② 放行端口（云厂商安全组 + 系统防火墙，两处都要）**

腾讯云轻量：实例 → 防火墙 → 添加规则；CVM：安全组 → 入站规则。两条：

| 协议端口 | 来源 | 用途 |
| --- | --- | --- |
| TCP:7000 | 0.0.0.0/0 | frp 控制通道 |
| TCP:18080 | 0.0.0.0/0 | 对外暴露 Jenkins |

```bash
# 系统里还开了 firewalld 的话
sudo firewall-cmd --permanent --add-port=7000/tcp --add-port=18080/tcp && sudo firewall-cmd --reload
```

**③ 客户端（Win11，Jenkins 所在的机器）**

下载 `frp_0.72.0_windows_amd64.zip`（GitHub 慢就同样加 `https://ghfast.top/` 前缀），解压到 `C:\frp`，删掉 `frps.exe`、`frps.toml`，新建 `C:\frp\frpc.toml`：

```toml
serverAddr = "49.234.202.181"
serverPort = 7000

auth.method = "token"
auth.token = "和服务器 frps.toml 完全相同"

[[proxies]]
name = "jenkins"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080
remotePort = 18080
```

启动并验证（本机 Jenkins 要先开着）：

```powershell
C:\frp\frpc.exe -c C:\frp\frpc.toml
# 成功标志：login to server success + start proxy success
```

然后**用手机流量**（别用公司 WiFi）打开 `http://49.234.202.181:18080`，能看到 Jenkins 登录页就说明全链路通了。

最后做开机自启，否则重启电脑 Webhook 就断：

```powershell
# 方式一：任务计划程序（无需装第三方工具）
schtasks /create /tn "frpc" /tr "C:\frp\frpc.exe -c C:\frp\frpc.toml" /sc onstart /ru SYSTEM /rl highest

# 方式二：nssm 注册成服务，可自动重启进程，更稳
nssm install frpc C:\frp\frpc.exe -c C:\frp\frpc.toml
nssm set frpc Start SERVICE_AUTO_START
nssm start frpc
```

**④ 接到 Jenkins 与 Git 仓库上**

1. Jenkins → Manage Jenkins → System → **Jenkins URL** 填 `http://49.234.202.181:18080/`（不填对，邮件和构建里的链接全是 localhost）。
2. GitHub 仓库 → Settings → Webhooks → Add webhook：
   - Payload URL：`http://49.234.202.181:18080/github-webhook/`（**结尾斜杠不能少**）
   - Content type：`application/json`
   - Secret：填 Jenkins 里 `github-webhook-token` 的值
   - 事件：`Just the push event`，勾上 Active
3. GitLab 仓库 → Settings → Webhooks：
   - URL：`http://49.234.202.181:18080/project/任务名`（GitLab 插件路径规则不同，见下方表格）
   - Trigger：`Push events`、`Merge request events`
4. 保存后点 **Redeliver / Test**，返回 200 且 Jenkins 立刻出现构建即成功。

> **快速演示的备选**：完全不想碰服务器时，用 cpolar / ngrok 临时暴露一节演示即可，但**别写进团队配置**——域名会变。
>
> **注意安全**：18080 一开，等于把 Jenkins 挂到公网。管理员密码必须强，教学环境不要放真实生产凭据；演示完 `sudo systemctl stop frps` 或删掉安全组规则即恢复本地。

#### 路线 B：轮询（最省事，延迟可接受）

```groovy
triggers {
    pollSCM('H/5 * * * *')   // 每 5 分钟检查一次，H 会打散到不同分钟避免拥堵
}
```

延迟平均 2.5 分钟，对学习和小团队完全够用。**配好路线 A 之后可以保留它做兜底**：Webhook 偶发丢失（GitHub 重投失败、穿透断过）时，轮询还能补上。

#### 路线 C：把 Jenkins 放到有公网的服务器（企业最终形态）

路线 A 是"Jenkins 留在本机、只把入口暴露出去"；这条路是把 **Jenkins 本身**部署在有公网 IP 的机器上（或内网机器 + 反代），不需要任何穿透，这是生产做法。第 17 章会讲"CI 机到底应该放哪"。

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
    def registry  = cfg.registry  ?: 'ghcr.io'
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
        credentialsId: cfg.registryCredentialId ?: 'ghcr-registry',
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
| Webhook 显示超时/连不上 | Jenkins 在内网，公网够不着 | 用 frp 自建穿透（路线 A）、或改轮询、或把 Jenkins 放公网机 |
| frpc 报 `dial tcp ...:7000: i/o timeout` | 云安全组/防火墙没放行 7000，或公司网络拦非标端口出站 | 先放行 TCP 7000；仍不通就把两端控制端口都改成 443 |
| `tar: Unexpected EOF in archive` / `gzip: stdin: unexpected end of file` | 压缩包下载不完整（中断后重名、镜像限速被截断） | 解压前先 `gzip -t` 校验；残缺包删掉重下，GitHub 慢就加 `https://ghfast.top/` 前缀 |
| `Cannot mkdir: Permission denied` | 在 `/opt` 等目录普通用户无写权限 | 命令前加 `sudo`，或先在家目录操作再 `sudo mv` |
| 重启电脑后 Webhook 又失效 | frpc 没设开机自启 | 任务计划程序 `schtasks /sc onstart`，或用 nssm 注册服务 |
| Multibranch 扫不到分支 | 仓库凭据无读权限，或过滤规则排除 | 检查凭据；看 Scan 日志 |
| Jenkinsfile 改了不生效 | 任务用的是"界面脚本"而非 SCM | 任务配置里改成 Pipeline script from SCM |
| `@Library` 报 `No such library` | 名字拼错 / 版本不对 / 路径配错 | 核对 Global Pipeline Libraries 的 Name 与 Library Path |
| 共享库函数报 `MissingPropertyException` | `vars/` 文件名与函数名不一致 | `vars/buildImage.groovy` 里必须是 `def call(...)` |
| 凭据日志变明文 | 用了 `echo` + 字符串拼接/编码 | 改用 `withCredentials` 原生绑定，别二次加工 |
| `docker: command not found` | Jenkins 容器里没装 Docker CLI | 给 Jenkins 容器挂载宿主 Docker（`/var/run/docker.sock`）并装 CLI，或改用能跑 docker 的 Agent |
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
- [ ] 内网穿透用的是固定地址（frp 自建），重启电脑后 Webhook 依然可用
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
