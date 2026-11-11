# 附录 A 命令速查

> 全书高频命令按场景归档，可直接复制。`【本地】`= Windows 开发机，`【服务器】`= yengxun-yun，`【容器】`= 容器内。

## SSH 与文件传输

```powershell
# 【本地】免密连接 / 执行单命令 / 传文件
ssh yengxun-yun
ssh yengxun-yun "uname -r"
scp .\scripts\deploy.sh yengxun-yun:/tmp/
scp -r .\demos\frontend\dist yengxun-yun:/tmp/

# 【本地】批量推送公钥（首次配置，需输一次密码）
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@49.234.202.181 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Docker / Compose

```bash
# 【服务器】镜像与容器
docker images | head                       # 本地镜像
docker build -f deploy/Dockerfile.backend -t cicd-demo-backend:42 demos/backend
docker save cicd-demo-backend:42 | gzip > b.tar.gz
gunzip -c b.tar.gz | docker load           # 无仓库路径导入
docker pull ccr.ccs.tencentyun.com/cicd-demo/cicd-demo-backend:42

docker compose -f docker-compose.yml --env-file .env up -d --remove-orphans
docker compose ps
docker compose logs --tail 60 api
docker compose exec api sh
docker compose down --remove-orphans        # 注意：不加 -v 才不会删卷

docker inspect -f '{{.State.Health}}' <容器>
docker stats --no-stream                   # 资源快照
docker system df                           # 磁盘占用分布
docker image prune -f                      # 清悬空镜像

# 【服务器】容器健康与日志
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker logs --tail 50 -f <容器>
docker exec <容器> whoami                  # 应为 appuser（非 root 验证）
```

## 诊断"第一分钟"

```bash
# 【服务器】出问题时按顺序跑
free -h                                    # 内存
df -h /                                    # 磁盘
uptime                                     # 负载
sudo ss -tlnp | grep -E ':80|:443|:8000'   # 端口
dmesg -T | grep -i 'killed process'        # OOM 记录
journalctl -u nginx --since "10 min ago"   # 系统服务日志
```

## Nginx 与证书

```bash
# 【容器/服务器】配置与证书
nginx -t                                   # 配置语法
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName
openssl s_client -connect 49.234.202.181:443 </dev/null 2>/dev/null | openssl x509 -noout -dates
openssl x509 -in server.crt -noout -checkend 2592000 && echo "30 天内不会过期"

curl -I http://49.234.202.181/             # 应 301
curl -kI https://49.234.202.181/           # 应 200
curl --cacert ca.crt https://49.234.202.181/healthz   # 证书链校验
```

## Git（发布视角）

```bash
git ls-files --eol | grep eol=crlf         # CRLF 残留检查（应为空）
git rev-parse --short=7 HEAD               # 短 sha（打镜像 tag 用）
git tag -a v1.2.0 -m "release v1.2.0" && git push origin v1.2.0
git revert HEAD                            # 撤销上次提交（实验后恢复）
```

## 部署与回滚

```bash
# 【服务器】
sudo TAG=<tag> bash /opt/apps/cicd-demo/scripts/deploy-local.sh   # 无仓库路径
sudo REGISTRY=... REGISTRY_NAMESPACE=... bash scripts/deploy.sh <tag>   # 仓库路径
sudo bash scripts/rollback.sh --list
sudo bash scripts/rollback.sh              # 回到上一版
readlink -f /opt/apps/cicd-demo/current    # 当前版本目录
```

## 备份 / 恢复 / 清理

```bash
# 【服务器】
sudo bash scripts/backup-data.sh
gunzip -c backups/app-<时间>.db.gz > /tmp/restore.db
sudo install -m 600 -o 10001 -g 10001 /tmp/restore.db shared/data/app.db
sudo bash scripts/cleanup.sh --aggressive
docker compose stop api                    # 恢复前先停写
```

## Jenkins 容器

```powershell
# 【本地】
docker compose -f pipelines/jenkins/docker-compose.jenkins.yml up -d
docker compose -f pipelines/jenkins/docker-compose.jenkins.yml logs -f jenkins
docker exec cicd-tutorial-jenkins-1 cat /var/jenkins_home/secrets/initialAdminPassword
```
