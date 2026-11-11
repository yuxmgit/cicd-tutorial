# 生产机只读探测记录（yengxun-yun）

- 时间：2026-11-11 14:17 CST
- 目标：腾讯云 CVM，SSH 别名 `yengxun-yun`，公网 `49.234.202.181`，用户 `ubuntu`
- 方式：`scripts/probe-server.sh`，只读，未做任何修改
- 用途：第 11 章的"动手前先看清家底"原始素材

## 一、真实输出

```text
==================== 1. 系统 ====================
PRETTY_NAME="Ubuntu 26.04 LTS"
VERSION_ID="26.04"
内核: 7.0.0-30-generic
架构: x86_64
主机: VM-0-11-ubuntu

==================== 2. CPU / 内存 ====================
CPU 核数: 4
               total        used        free      shared  buff/cache   available
Mem:           3.6Gi       707Mi       2.0Gi       2.2Mi       1.2Gi       2.9Gi
Swap:          2.0Gi          0B       2.0Gi
--- 内存大户 Top5 ---
ubuntu       0.3%    130MB  /home/ubuntu/.codebuddy-server-cn/bin/stable-.../node
ubuntu       0.1%     81MB  /home/ubuntu/.codebuddy-server-cn/bin/stable-.../node
root         1.2%     65MB  /usr/local/qcloud/YunJing/YDEyes/YDService
root         0.0%     32MB  /usr/bin/python3
root         0.0%     29MB  /usr/bin/python3

==================== 3. 磁盘 ====================
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda3        39G  6.0G   32G  17% /
--- inode ---
/dev/vda3      2583616 133682 2449934    6% /

==================== 4. Swap ====================
NAME      TYPE SIZE USED PRIO
/swap.img file   2G   0B   -1

==================== 5. 时间与时区 ====================
Local time: Wed 2026-11-11 14:17:22 CST
Time zone: Asia/Shanghai (CST, +0800)
System clock synchronized: yes

==================== 6. 已装工具 ====================
docker          NOT INSTALLED
git             /usr/bin/git
curl            /usr/bin/curl
wget            /usr/bin/wget
nginx           NOT INSTALLED
java            NOT INSTALLED
node            NOT INSTALLED
python3         /usr/bin/python3
pip3            NOT INSTALLED
make            /usr/bin/make
ufw             /usr/sbin/ufw
fail2ban-client NOT INSTALLED
certbot         NOT INSTALLED

==================== 7. 版本 ====================
Python 3.14.4

==================== 8. 监听端口 ====================
LISTEN 0 4096  127.0.0.54:53      0.0.0.0:*
LISTEN 0 511   127.0.0.1:43557    0.0.0.0:*
LISTEN 0 4096  127.0.0.53%lo:53   0.0.0.0:*
LISTEN 0 4096  0.0.0.0:22         0.0.0.0:*
LISTEN 0 4096  [::]:22            [::]:*

==================== 10. 防火墙 ====================
ufw 未启用

==================== 11. 结论 ====================
可用内存: 3001 MiB
根分区可用: 32G
内存余量正常
```

## 二、解读与对教程的影响

| 发现 | 含义 | 决策 |
| --- | --- | --- |
| Ubuntu **26.04 LTS**，内核 7.0 | 比预想新两个大版本 | 全部命令按 26.04 实测；`apt` 系；Docker 官方源需确认支持 26.04 代号 |
| **4 核 / 3.6 GiB** | 比计划的 2G 宽裕，能同时跑前后端 + Nginx | 仍坚持"Jenkins 不上生产机"（构建峰值会挤占业务） |
| 磁盘 39G，剩 32G | 空间充足 | 仍需日志轮转与镜像清理，40G 撑不住长期堆积 |
| Swap 2G（/swap.img） | 已有，无需再建 | 保留，作为 OOM 兜底 |
| Python **3.14.4** | 系统 Python 太新，部分依赖无 wheel | **应用一律跑在 `python:3.11-slim` 容器里**，不用系统 Python 跑生产 |
| Docker / Nginx **未装** | 干净机器 | 第 11 章负责安装（含国内镜像加速） |
| 80/443 **空闲** | 不用绕端口 | 站点直接用 80/443 + HTTPS |
| 仅 22 在监听 | 干净，无历史包袱 | 安全组只需放通 22/80/443 |
| ufw 未启用 | 系统防火墙关闭 | 与腾讯云安全组形成"两层"，第 11 章同时配置 |
| 有 codebuddy-server 进程（约 210MB） | 远程开发服务在跑 | 部署时注意内存余量，别把 available 吃光 |

## 三、待办

- [ ] 安装 Docker（第 11 章）
- [ ] 安装 Nginx（第 11 章）
- [ ] 创建部署用户与目录规范（第 11 章）
- [ ] SSH 加固（禁用密码登录，需先验证密钥登录可用）
- [ ] 安全组放通 80/443（控制台操作）
