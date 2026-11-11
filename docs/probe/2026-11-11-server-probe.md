# 服务器只读探测记录（对照案例机：huawei-yun）

> **结论先行：这台机器不作为部署目标。** 正式部署机是腾讯云 `yengxun-yun`（`49.234.202.181`，用户 `ubuntu`）。
> 本文保留作为第 11 章"怎么判断一台机器适不适合做生产机"的真实反面案例：内存 available 仅 14Mi、80/443 被宝塔占用、暴露邮件与 FTP 端口。

- 时间：2026-11-11 13:19 CST
- 目标：SSH 别名 `huawei-yun`（124.70.96.225）
- 性质：全部为只读命令，未做任何修改
- 用途：第 11 章的"动手前先看清你家厨房"实操素材

## 一、系统与资源（真实输出）

```text
===OS===
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
6.8.0-124-generic

===CPU/MEM===
2
               total        used        free      shared  buff/cache   available
Mem:           1.7Gi       1.7Gi        54Mi       4.0Mi        76Mi        14Mi
Swap:          2.0Gi          0B       2.0Gi

===DISK===
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        40G   12G   26G  32% /

===SWAP===
NAME      TYPE SIZE USED PRIO
/swapfile file   2G   0B   -2

===TIME===
Local time: Wed 2026-11-11 13:19:58 CST
Time zone: Asia/Shanghai (CST, +0800)
```

**解读**：
1. 系统是 **Ubuntu 24.04.4**（此前以为是 22.04），内核 6.8——教程全部按 24.04 实测。
2. **内存红灯**：2G 中 used 已达 1.7Gi，available 仅 14Mi——比规划时预估的更紧张，部署前必须先解决内存。
3. Swap 2G 已存在（好事，说明有人配置过）；时区正确；磁盘还有 26G 可用。

## 二、已装软件与监听端口（真实输出，节选）

```text
===TOOLS===
docker     /usr/bin/docker        Docker 29.9.3 + Compose v5.7.0
nginx      /usr/bin/nginx         nginx/1.30.6
git        /usr/bin/git
node       /usr/bin/node
python3    /usr/bin/python3
ufw        /usr/sbin/ufw
java       NOT INSTALLED
fail2ban   NOT INSTALLED
certbot    NOT INSTALLED

===LISTEN（关键项）===
0.0.0.0:22    sshd                 SSH（保留）
0.0.0.0:21    pure-ftpd            FTP 服务
0.0.0.0:25/465/587  master         Postfix 邮件
0.0.0.0:110/143/993/995 dovecot   收信服务
0.0.0.0:80    nginx                已被占用
0.0.0.0:888   nginx                宝塔 phpMyAdmin 风格入口
0.0.0.0:8888  BT-Panel             宝塔面板
0.0.0.0:13306 docker-proxy         MySQL 容器
0.0.0.0:7979 / 15700  docker-proxy 另外两个运行中容器
```

**解读**：
1. 这是一台**宝塔面板机器**（BT-Panel 实例名也印证了），不是干净机器。
2. 上面跑着**邮件全家桶**（Postfix + Dovecot + Rspamd）、FTP、多个 Docker 容器——内存被吃掉的大头大概率在这里（待 `ps --sort=-rss` 确认）。
3. 80/443/888/8888 已被占用：我们的站点必须用**独立端口**或与宝塔 Nginx 共存。
4. Docker、Nginx、Node 都是现成的，第 11 章安装工作量比预期小，重点变成"共存与内存治理"。
5. 邮件（25/110/143/465/587/993/995）与 FTP（21）端口直接暴露公网，第 19 章安全章节会复盘这个风险。

## 三、待确认事项

- [ ] 内存大户精确名单（`ps aux --sort=-rss`，探测命令已下发，等待回传）
- [ ] 这台机器是否需要收发邮件（决定能否停用邮件服务释放内存）
- [ ] FTP 是否在用（同上）
- [ ] 运行中的三个容器（13306 / 7979 / 15700）分别是什么、是否可动
