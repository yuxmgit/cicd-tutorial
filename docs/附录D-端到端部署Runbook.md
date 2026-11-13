# 附录 D 端到端部署 Runbook

> 用途：一条清单走完"改代码 → 提交 → 自动测试 → 构建镜像 → 自动部署 → 验证"的完整闭环。
> 本文所有地址、凭据 ID、路径都对应本书实操环境，可直接照做。前置知识：第 3～5 章（Jenkins）、第 10 章（镜像仓库）、第 11/15 章（服务器与部署脚本）。

---

## 0. 环境快照（先对号入座）

| 项目 | 值 |
| --- | --- |
| Jenkins 位置 | 本机 Win11，`http://localhost:8080` |
| Jenkins 公网入口 | `http://49.234.202.181:18080`（frp 隧道，本机 frpc + 云端 frps） |
| 部署目标服务器 | `ubuntu@49.234.202.181`（腾讯云） |
| 代码仓库 | `github.com/yuxmgit/cicd-tutorial` |
| 分支保护 | main：**必须走 PR** + **禁止 merge commit**（只能 Squash/Rebase） |
| 镜像仓库 | GHCR `ghcr.io`，命名空间（GitHub 用户名）`yxm1989614` |
| 应用访问 | `http://49.234.202.181/`（前端 80） |

**Jenkins 凭据清单**（Manage Jenkins → Credentials，缺一条就先补，见第 5 章步骤 1）：

| ID | 类型 | 用途 |
| --- | --- | --- |
| `deploy-ssh-key` | SSH Username with private key | 部署时 ssh 到服务器 |
| `ghcr-registry` | Username with password | `docker login` 推镜像（填 GitHub 用户名 + PAT，不是服务器账号） |
| `github-repo-readonly` | Username with password（GitHub 用户名 + PAT） | Multibranch 拉代码 |
| `github-webhook-token` | Secret text | Webhook 校验 |

**两条「Username with password」凭据怎么填（详细流程）**——`ghcr-registry` 和 `github-repo-readonly` 本质都是 GitHub 用户名 + PAT，但权限要求不同，建议分成两个 token 生成，权限最小化，泄露时可单独吊销：

**① `ghcr-registry`（docker login 推镜像用）**

1. 生成能推包的 PAT：GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → Generate new token (classic)；Note 随便填（如 `ghcr-push`），选好 Expiration，**勾选 scope `write:packages`**（自动带上 `read:packages`，不用勾 `repo`）
2. 点 Generate 后**立刻复制** token（`ghp_` 开头，只显示一次）
3. Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials：
   - Kind：`Username with password`
   - Username：**GitHub 用户名**（与 GHCR 命名空间一致，全小写；用户名写错是 `denied` 的常见原因）
   - Password：粘贴刚才的 PAT（**不是 GitHub 登录密码**）
   - ID：`ghcr-registry`
4. 验证：在本机或服务器执行 `docker login ghcr.io -u <GitHub用户名>`，Password 处粘贴 PAT，看到 `Login Succeeded` 才算通过；仍 denied 则检查 token 是否过期、是否勾了 `write:packages`、用户名大小写是否与 GitHub 一致

**② `github-repo-readonly`（Multibranch 拉代码用，只读权限即可）**

1. 生成只读 PAT（二选一）：
   - **classic**：只勾 `repo`（私有仓库必须，公开仓库可不勾）
   - **fine-grained**（推荐）：Repository access 选本仓库，Permissions → Contents 设为 **Read-only**
2. Jenkins → Add Credentials，Kind 同样选 `Username with password`：
   - Username：GitHub 用户名
   - Password：粘贴这个只读 PAT
   - ID：`github-repo-readonly`（⚠️ 凭据 ID 必须与 Multibranch 配置、Jenkinsfile 里引用的 `credentialsId` **完全一致**，多一个少一个横杠都会报找不到凭据）
3. 验证：Multibranch 的 Branch Sources → Credentials 下拉里能选中它，且扫分支能拉到代码

---

## 1. 一次性准备（逐项打勾）

### 1.1 Jenkins 侧

- [ ] **插件**：Git、GitHub、Pipeline、Multibranch 相关插件装齐（Manage Jenkins → Plugins；装了 `Pipeline` 基本都带了）
- [ ] **Jenkins URL**：Manage Jenkins → System → `http://49.234.202.181:18080/`
- [ ] **4 条凭据**全部建好
- [ ] **frp 双端在线**：服务器 `systemctl status frps` 是 running；本机 `C:\frp\frpc.exe` 进程在跑（手机流量访问 `http://49.234.202.181:18080` 能看到登录页）

### 1.2 GitHub 侧

- [ ] **PAT**：GitHub → Settings → Developer settings → Personal access tokens，classic 勾 `repo`（或 fine-grained 只给 Contents: Read-only），填进 `github-repo-readonly` 凭据
- [ ] **Webhook**：仓库 → Settings → Webhooks：
  - Payload URL：`http://49.234.202.181:18080/github-webhook/`（结尾斜杠不能少）
  - Content type：`application/json`；Secret：`github-webhook-token` 的值
  - 事件：`Just the push event`
  - 验证标准：Recent Deliveries 里有 `ping` 事件且 **Response 200**
- [ ] **分支保护**：Settings → Rules → Rulesets（或 Branches）确认 main 有：Require a pull request + 不允许 merge commit（已配好）

### 1.3 服务器侧（49.234.202.181）

- [ ] Docker 与 compose 插件可用（第 11 章 `scripts/init-server.sh`）
- [ ] **部署目录与文件**就位（第 15 章步骤 1 的简版）：

```powershell
# 本机上传（PowerShell）
scp scripts/deploy.sh scripts/healthcheck.sh deploy/docker-compose.prod.yml ubuntu@49.234.202.181:/tmp/
```

```bash
# 服务器归位（与第 15 章步骤 1 的布局一致：脚本进 scripts/，compose 进 shared/）
sudo mkdir -p /opt/apps/cicd-demo/shared/nginx /opt/apps/cicd-demo/scripts
sudo mv /tmp/deploy.sh /tmp/healthcheck.sh /opt/apps/cicd-demo/scripts/
sudo mv /tmp/docker-compose.prod.yml /opt/apps/cicd-demo/shared/
sudo chmod +x /opt/apps/cicd-demo/scripts/*.sh
# deploy.sh 用 $(dirname $0) 找同目录的 healthcheck.sh（scripts/ 里正好是兄弟），
# 并按 ${APP_BASE_DIR}/shared/docker-compose.prod.yml 找编排文件——两处都能对上
```

- [ ] **Nginx 站点配置**：`/opt/apps/cicd-demo/shared/nginx/site.conf` 存在（第 13 章），并映射 80 端口
- [ ] **GHCR 登录过一次**（否则推镜像时没有权限）：

```bash
docker login ghcr.io   # 输入 ghcr-registry 凭据里那组账号密码
```

> **还没配好 GHCR？** 先按第 15 章步骤 3～5 用 `docker save` 手工部署跑通，本文档的 ⑥⑦ 两个 stage 暂时注释掉，其余照常。

---

## 2. 仓库里放 `Jenkinsfile`（根目录）

把下面内容存为仓库根目录的 `Jenkinsfile`（基于 `pipelines/jenkins/Jenkinsfile-04-backend` 扩展了前端构建和部署 stage）。**注意把 `NAMESPACE` 换成你自己的 GitHub 用户名（GHCR 命名空间，全小写）**：

```groovy
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds(abortPrevious: true)
    }

    environment {
        REGISTRY      = 'ghcr.io'
        NAMESPACE     = 'yxm1989614'                   // ← GitHub 用户名（GHCR 命名空间）
        APP_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        IMAGE_BACKEND = "${REGISTRY}/${NAMESPACE}/cicd-demo-backend:${APP_TAG}"
        IMAGE_FRONTEND= "${REGISTRY}/${NAMESPACE}/cicd-demo-frontend:${APP_TAG}"
        DEPLOY_HOST   = 'ubuntu@49.234.202.181'
        DEPLOY_SCRIPT = '/opt/apps/cicd-demo/scripts/deploy.sh'
    }

    stages {
        stage('① 检出') {
            steps { sh 'git log -1 --oneline' }
        }

        stage('② 后端测试') {
            agent {
                docker {
                    image 'python:3.11-slim'
                    args '-v jenkins-pip-cache:/root/.cache/pip'
                    reuseNode true
                }
            }
            steps {
                dir('demos/backend') {
                    sh 'pip install -r requirements.txt'
                    sh 'pytest'
                }
            }
        }

        stage('③ 构建镜像') {
            steps {
                sh "docker build -f deploy/Dockerfile.backend  -t ${IMAGE_BACKEND}  demos/backend"
                sh "docker build -f deploy/Dockerfile.frontend -t ${IMAGE_FRONTEND} demos/frontend"
            }
        }

        stage('④ 冒烟测试') {
            steps {
                sh '''
                    docker rm -f smoke-api 2>/dev/null || true
                    docker run -d --name smoke-api -p 18000:8000 "$IMAGE_BACKEND"
                    for i in $(seq 1 20); do
                        if curl -fsS http://127.0.0.1:18000/healthz >/dev/null; then
                            echo "冒烟测试通过（第 ${i} 次）"; exit 0
                        fi
                        sleep 2
                    done
                    echo "冒烟测试失败，容器日志："; docker logs smoke-api; exit 1
                '''
            }
            post {
                always { sh 'docker rm -f smoke-api 2>/dev/null || true' }
            }
        }

        // ⑤⑥ 只在 main 跑：feature 分支只做"测试+构建+冒烟"，绝不碰生产
        stage('⑤ 推送镜像') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr-registry',
                                                  usernameVariable: 'REG_USER',
                                                  passwordVariable: 'REG_PASS')]) {
                    sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ghcr.io'
                    sh "docker push ${IMAGE_BACKEND}"
                    sh "docker push ${IMAGE_FRONTEND}"
                }
            }
        }

        stage('⑥ 部署生产') {
            when { branch 'main' }
            steps {
                // 想加人工确认就把下面 input 的注释打开
                // input message: '确认部署生产？', ok: '部署', submitter: 'admin'
                withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key',
                                                   keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST} \
                          'sudo REGISTRY=${REGISTRY} REGISTRY_NAMESPACE=${NAMESPACE} \
                             bash ${DEPLOY_SCRIPT} ${APP_TAG}'
                    """
                }
            }
        }
    }

    post {
        failure { echo "构建失败：${env.BUILD_URL}console" }
        success { echo "本次构建完成，TAG=${APP_TAG}" }
        cleanup { cleanWs() }
    }
}
```

> **要点**：
> - `APP_TAG = 构建号-短commit`，镜像、服务器版本目录、日志里的版本号三者能互相印证
> - 部署用的是仓库里现成的 `scripts/deploy.sh`（拉镜像 → 版本目录 → 切软链 → 健康检查 → 失败自动回滚）
> - Groovy 双引号里的 shell 变量要写 `\$SSH_KEY`，否则被 Groovy 先吃掉（第 5 章练习 2）

提交这个文件（不能直推 main，走流程）：

```powershell
git switch -c feature/jenkinsfile
git add Jenkinsfile
git commit -m "ci: 添加端到端流水线 Jenkinsfile"
git push -u origin feature/jenkinsfile
```

然后 GitHub 上开 PR → **Squash and merge**（你的 main 只认这个）。

---

## 3. Jenkins 建 Multibranch Pipeline（逐字段）

**新建任务 → Multibranch Pipeline**，名称建议 `cicd-demo`：

| 配置项 | 值 |
| --- | --- |
| Branch Sources → Add source | GitHub |
| Repository HTTPS URL | `https://github.com/yuxmgit/cicd-tutorial.git` |
| Credentials | `github-repo-readonly`（只读 PAT 就够） |
| Behaviors | 保留 Discover branches；可加 Discover pull requests from origin |
| Property strategy | All branches get the same properties |
| Build Configuration → Mode | `by Jenkinsfile`（**不要选 by SCM 自动**） |
| Script Path | `Jenkinsfile` |
| Scan Repository Triggers | 勾 Periodically if not hooked otherwise，间隔填 `1 day`（webhook 兜底） |

保存后自动扫描，`main` 和已有 `feature/*` 都会各生成一个子任务。

> 之前的 `hello-pipeline`（普通 Pipeline）是练习用的，确认 Multibranch 跑通后可以 Disable 掉，避免两个任务重复构建。

---

## 4. 日常提交流程（背下来这一套）

### 4.1 标准功能流

```powershell
# ① 从最新 main 开分支
git switch main
git pull
git switch -c feature/order-page        # 分支名：feature/xxx | fix/xxx | chore/xxx

# ② 改代码，分小步提交
git add demos/backend/app/main.py
git commit -m "feat: 新增订单接口"

# ③ 推上去（此时 Jenkins 自动建 feature/order-page 子任务并跑测试）
git push -u origin feature/order-page

# ④ GitHub 开 PR（base: main ← compare: feature/order-page）
#    等 PR 上的 Jenkins 检查变绿（这就是你的 CI 门禁）

# ⑤ Squash and merge → 确认 → 删除分支（页面上的按钮）

# ⑥ 本地收尾
git switch main
git pull
git branch -d feature/order-page
git push origin --delete feature/order-page
```

⑤ 合并完成的那一刻起**全自动**：webhook → Jenkins main 任务 → 测试/构建/冒烟 → 推镜像 → ssh 部署 → 健康检查。

### 4.2 提交信息规范（Conventional Commits 精简版）

| 前缀 | 用途 | 例 |
| --- | --- | --- |
| `feat:` | 新功能 | `feat: 订单列表分页` |
| `fix:` | 修 bug | `fix: 登录态过期后无限刷新` |
| `ci:` | 流水线/构建相关 | `ci: 冒烟测试加超时` |
| `docs:` | 只改文档 | `docs: 补充部署说明` |
| `refactor:` | 重构不改行为 | `refactor: 抽取鉴权中间件` |
| `chore:` | 杂务 | `chore: 升级依赖` |

### 4.3 红线（你的分支保护会替你把关，但别想着绕）

- ❌ 直推 main（规则拒绝）
- ❌ 本地 merge main 再推（规则拒绝 merge commit）
- ❌ `git push --force` 到 main（**永远不要**）
- ❌ 在 feature 分支上直接改 `when { branch 'main' }` 的 stage 让它提前跑

---

## 5. 合并后发生了什么（心中要有这张图）

```text
Squash merge 到 main
  → GitHub 发 push 事件 → 49.234.202.181:18080 (frps)
  → 隧道 → 本机 Jenkins Multibranch 的 main 子任务
  → ① 检出 → ② pytest → ③ 构建 backend/frontend 镜像 → ④ 冒烟
  → ⑤ docker push 到 GHCR（tag: 构建号-短commit）
  → ⑥ ssh 到服务器执行 deploy.sh：
       拉镜像 → 新版本目录 releases/时间戳-TAG → 切 current 软链
       → docker compose up -d → 健康检查 /healthz（失败自动回滚旧版本）
  → 浏览器访问 http://49.234.202.181/ 看到新版本
```

---

## 6. 端到端验证（照做一遍，全过才算通）

### 场景 A：feature 分支只测不部署

```powershell
git switch -c feature/verify-a
git commit --allow-empty -m "chore: 验证分支隔离"
git push -u origin feature/verify-a
```

- Jenkins 几秒~1 分钟内出现 `feature/verify-a` 子任务并自动构建
- 构建日志：①②③④ 执行，**⑤⑥ 显示 Skipped**（不是 main）
- GitHub PR 页面出现 Jenkins 的检查记录
- 验证完删分支

### 场景 B：合并 main 自动部署

改一个肉眼可见的东西，如 `demos/frontend` 页面标题文字，按 4.1 完整走一遍。合并后：

1. Jenkins main 任务自动构建，全部 stage 绿
2. 控制台日志末尾有 `部署完成：TAG=xx-xxxxxxxx`
3. 服务器验证版本指纹：

```bash
cat /opt/apps/cicd-demo/current/VERSION          # 应等于 Jenkins 的 APP_TAG
readlink -f /opt/apps/cicd-demo/current          # 指向最新 releases 目录
docker ps --format '{{.Names}} {{.Image}}'       # 镜像 tag 一致
curl -fsS http://127.0.0.1:8000/healthz && echo OK
```

4. 本机浏览器（或 curl）访问 `http://49.234.202.181/`，看到改动生效

### 场景 C：坏版本自动回滚（可选但强烈建议）

临时改 `demos/backend` 让 `/healthz` 返回 500（参考第 15 章演示二），走 PR 合并：

- 部署 stage 失败，日志出现"健康检查失败 + 回滚到上一版本"
- `cat /opt/apps/cicd-demo/current/VERSION` 回到旧 TAG
- 线上服务全程无中断
- **改回来再走一次 PR**

### 场景 D：Webhook 兜底验证（可选）

停掉本机 frpc（关掉 `frpc.exe` 窗口），推一个空提交。兜底生效时间 = 第 3 节配的扫描间隔（默认 `1 day`，即最长 1 天才触发）；想当场验证，先把 Multibranch 的 Scan Repository Triggers 临时改成 `5 分钟`，测完改回。测完记得把 frpc 启动回来。

---

## 7. 发布失败怎么办（处置顺序）

| 情况 | 动作 |
| --- | --- |
| Jenkins 某个 stage 红 | 看构建日志定位 stage；②红了修代码，④红了看容器日志，⑥红了看服务器 |
| 部署了坏版本 | `deploy.sh` 已自动回滚；人工再回滚：`sudo bash /opt/apps/cicd-demo/scripts/rollback.sh`（第 15 章） |
| 构建根本没触发 | GitHub Webhook Recent Deliveries 看最近 push 事件：无记录→GitHub/网络问题；有记录非 200→路径/Secret；200 但没构建→看 Jenkins 系统日志，检查 frpc 是否在跑 |
| 镜像推送 401 | `ghcr-registry` 凭据账号密码错；服务器拉取失败则是服务器没 `docker login` |
| 部署 ssh 失败 | `deploy-ssh-key` 私钥与服务器 `authorized_keys` 不匹配，先用本地 `ssh -i` 复现 |

更多排错对照：第 5 章"五、坑与排错"、第 15 章"五、坑与排错"。

---

## 8. 最终验收清单

- [ ] `Jenkinsfile` 在仓库根目录，Multibranch 任务按它跑
- [ ] 新推 feature 分支：Jenkins 自动出现子任务，只跑 ①～④，⑤⑥ Skipped
- [ ] PR 上能看到 Jenkins 检查，Squash 合并后 main 自动走完全流程
- [ ] `http://49.234.202.181/` 能访问，内容是最新版本
- [ ] 服务器 `current/VERSION` 与 Jenkins 构建号-短 commit 一致
- [ ] 人为破坏健康检查，能自动回滚且服务不中断
- [ ] frpc 重启电脑后自启（任务计划程序/nssm），Webhook 不失效
- [ ] 日志里凭据显示 `****`
