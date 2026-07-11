#!/bin/sh
# Let's Encrypt 최초 인증서 발급 부트스트랩.
# nginx 가 인증서 없이는 못 뜨므로 (1) 더미 인증서로 nginx 기동 → (2) 더미 삭제 →
# (3) 실제 인증서 발급 → (4) nginx reload 순으로 진행한다.
#
# 사용 전 아래 DOMAINS / EMAIL 을 실제 값으로 수정하고, DNS 가 이 서버를 가리키는지 확인할 것.
#   chmod +x init-letsencrypt.sh && ./init-letsencrypt.sh
set -e

DOMAINS="api.mediview.example.com admin.mediview.example.com mediview.example.com grafana.mediview.example.com"
EMAIL="admin@mediview.example.com"     # 만료 알림 수신 이메일
STAGING=0                              # 1 이면 스테이징(레이트리밋 회피 테스트용)

CONF="./certbot/conf"
WWW="./certbot/www"
mkdir -p "$CONF" "$WWW"

# 권장 TLS 파라미터 배치
if [ ! -e "$CONF/options-ssl-nginx.conf" ] || [ ! -e "$CONF/ssl-dhparams.pem" ]; then
  echo "### TLS 파라미터 다운로드..."
  curl -s https://raw.githubusercontent.com/certbot/certbot/main/certbot-nginx/src/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$CONF/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/main/certbot/certbot/ssl-dhparams.pem > "$CONF/ssl-dhparams.pem"
fi

for d in $DOMAINS; do
  echo "### [$d] 더미 인증서 생성..."
  mkdir -p "$CONF/live/$d"
  docker compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout '/etc/letsencrypt/live/$d/privkey.pem' \
      -out '/etc/letsencrypt/live/$d/fullchain.pem' \
      -subj '/CN=localhost'" certbot
done

echo "### nginx 기동..."
docker compose up -d nginx

for d in $DOMAINS; do
  echo "### [$d] 더미 인증서 삭제..."
  docker compose run --rm --entrypoint "rm -rf /etc/letsencrypt/live/$d /etc/letsencrypt/archive/$d /etc/letsencrypt/renewal/$d.conf" certbot

  echo "### [$d] 실제 인증서 발급..."
  STAGING_ARG=""
  [ "$STAGING" != "0" ] && STAGING_ARG="--staging"
  docker compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot $STAGING_ARG \
      --email $EMAIL --agree-tos --no-eff-email --non-interactive \
      -d $d" certbot
done

echo "### nginx reload..."
docker compose exec nginx nginx -s reload
echo "### 완료. 이후 갱신은 certbot 컨테이너가 자동 수행합니다."
