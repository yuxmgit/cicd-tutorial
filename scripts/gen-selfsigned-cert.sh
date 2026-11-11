#!/usr/bin/env bash
# 生成自签 CA + 服务器证书（无域名场景：用 IP 作为 SAN）
#
# 用法（在服务器的 shared/certs 目录执行）：
#   sudo bash scripts/gen-selfsigned-cert.sh 49.234.202.181
#
# 产物：
#   ca.crt       根证书（导入浏览器/客户端信任，或给 curl --cacert 用）
#   server.crt   服务器证书
#   server.key   服务器私钥（权限必须是 600）
#   san.cnf      本次签发的 SAN 配置（留档，便于复查）
set -euo pipefail

IP="${1:?用法: gen-selfsigned-cert.sh <服务器公网IP或域名>}"
OUT_DIR="${2:-.}"
DAYS_CA=3650
DAYS_SRV=825          # 825 天是现代浏览器对服务端证书的推荐上限
SUBJ_CA="/CN=CICD Demo Root CA/O=CICD Tutorial"
SUBJ_SRV="/CN=${IP}/O=CICD Tutorial"

cd "$OUT_DIR"

if [ -f server.crt ] && [ -f server.key ]; then
  echo "已存在 server.crt / server.key，跳过（要重签请先删除）"
  exit 0
fi

echo "=== 1. 生成根 CA（如果不存在）==="
if [ ! -f ca.key ]; then
  openssl req -x509 -newkey rsa:4096 -sha256 -days "$DAYS_CA" -nodes \
    -keyout ca.key -out ca.crt -subj "$SUBJ_CA" 2>/dev/null
  echo "已生成 ca.key / ca.crt"
else
  echo "已有 ca.key / ca.crt，复用"
fi

echo "=== 2. 生成服务器私钥与 CSR ==="
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "$SUBJ_SRV" 2>/dev/null

echo "=== 3. 写入 SAN 配置（现代浏览器只认 SAN，不认 CN）==="
# 判断是 IP 还是域名
if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SAN="IP:${IP},IP:127.0.0.1,DNS:localhost"
else
  SAN="DNS:${IP},DNS:www.${IP},IP:127.0.0.1"
fi
cat > san.cnf <<EOF
subjectAltName=${SAN}
extendedKeyUsage=serverAuth
EOF
echo "SAN: ${SAN}"

echo "=== 4. 用 CA 签发服务器证书 ==="
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days "$DAYS_SRV" -sha256 -extfile san.cnf 2>/dev/null

chmod 600 server.key
chmod 644 server.crt ca.crt

echo "=== 5. 自检 ==="
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName

echo
echo "完成。文件清单："
ls -l ca.crt server.crt server.key san.cnf
echo
echo "下一步："
echo "  1. 把 ca.crt 导入浏览器/系统信任（curl 可用 --cacert ca.crt）"
echo "  2. Nginx 配置指向 server.crt / server.key（已由 site.conf 引用）"
echo "  3. 重启前端容器：docker compose ... restart web"
