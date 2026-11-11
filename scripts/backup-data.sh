#!/usr/bin/env bash
# SQLite + 文件备份（带校验与保留策略）
#
# 用法：
#   sudo bash scripts/backup-data.sh
#   DATA_DIR=/opt/apps/cicd-demo/shared/data BACKUP_DIR=/backup KEEP_DAYS=7 bash scripts/backup-data.sh
#
# 为什么不用 cp：SQLite 在 WAL 模式下，正在写入时直接 cp 可能拿到不一致的快照。
# 正确做法是 sqlite3 的 .backup（在线热备），或用 Python 的 backup API。
set -euo pipefail

DATA_DIR="${DATA_DIR:-/opt/apps/cicd-demo/shared/data}"
BACKUP_DIR="${BACKUP_DIR:-/opt/apps/cicd-demo/shared/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
DB_FILE="${DB_FILE:-${DATA_DIR}/app.db}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET="${BACKUP_DIR}/app-${STAMP}.db"

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

[ -f "$DB_FILE" ] || { echo "数据库不存在：$DB_FILE"; exit 1; }
mkdir -p "$BACKUP_DIR"

log "1/4 在线备份 $DB_FILE"
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB_FILE" ".backup '${TARGET}'"
else
  log "未安装 sqlite3，使用 Python backup API"
  python3 - "$DB_FILE" "$TARGET" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
with sqlite3.connect(src) as s, sqlite3.connect(dst) as d:
    s.backup(d)
PY
fi
chmod 600 "$TARGET"
SIZE=$(du -h "$TARGET" | cut -f1)
log "备份完成：${TARGET}（${SIZE}）"

log "2/4 压缩"
gzip -f "$TARGET"
GZ="${TARGET}.gz"

log "3/4 校验压缩包完整性与可读性"
gzip -t "$GZ"
python3 - "$GZ" <<'PY'
import gzip, sqlite3, sys, tempfile, os
path = sys.argv[1]
with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
    tmp = f.name
try:
    with gzip.open(path, "rb") as src, open(tmp, "wb") as dst:
        dst.write(src.read())
    conn = sqlite3.connect(tmp)
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    count = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0] if "tasks" in tables else -1
    conn.close()
    print(f"校验通过：表 {tables}，tasks 行数 {count}")
finally:
    os.unlink(tmp)
PY

log "4/4 清理超过 ${KEEP_DAYS} 天的备份"
find "$BACKUP_DIR" -name 'app-*.db.gz' -type f -mtime "+${KEEP_DAYS}" -print -delete || true

log "完成。当前备份："
ls -lh "$BACKUP_DIR"/app-*.db.gz 2>/dev/null | tail -5 || true
