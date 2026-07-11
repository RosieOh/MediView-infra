#!/bin/sh
# mariadb 정기 백업 루프. 하루 1회 덤프(gzip) 후 보존기간 경과분을 삭제한다.
# 컨테이너로 상시 구동되며, 컨테이너 로그로 결과를 남긴다.
set -eu

: "${DB_HOST:=mariadb}"
: "${DB_NAME:=mediview}"
: "${DB_USER:=mediview}"
: "${RETENTION_DAYS:=7}"
BACKUP_DIR=/backups

mkdir -p "$BACKUP_DIR"

run_backup() {
  ts=$(date +%Y%m%d-%H%M%S)
  out="$BACKUP_DIR/${DB_NAME}-${ts}.sql.gz"
  echo "[backup] $(date -Iseconds) dumping $DB_NAME -> $out"
  if mariadb-dump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" \
        --single-transaction --quick --routines --events "$DB_NAME" | gzip > "$out"; then
    echo "[backup] OK ($(du -h "$out" | cut -f1))"
  else
    echo "[backup] FAILED — 불완전 파일 제거"
    rm -f "$out"
  fi
  # 보존: RETENTION_DAYS 초과 파일 삭제
  find "$BACKUP_DIR" -name "${DB_NAME}-*.sql.gz" -type f -mtime "+${RETENTION_DAYS}" -print -delete
}

# 기동 직후 1회 + 이후 24시간 주기
while :; do
  run_backup || echo "[backup] run 예외"
  sleep 86400 &
  wait $!
done
