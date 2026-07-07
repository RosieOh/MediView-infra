# Nginx 리버스 프록시

단일 진입점에서 TLS 종료 후 프론트/백엔드로 라우팅합니다.

| 도메인 | 대상 | 비고 |
|--------|------|------|
| `api.mediview.example.com` | Spring 백엔드 | `/api` REST, `/ws` WebSocket(업그레이드) |
| `admin.mediview.example.com` | 관리자(Next.js) | |
| `mediview.example.com` | 랜딩(Next.js) | |

## 적용
```bash
sudo cp mediview.conf /etc/nginx/conf.d/mediview.conf
# 도메인/업스트림 포트 수정
sudo nginx -t && sudo systemctl reload nginx
```

## TLS 발급 (certbot)
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d mediview.example.com -d api.mediview.example.com -d admin.mediview.example.com
```
발급 후 위 conf 의 `ssl_certificate*` 경로가 자동 구성됩니다. 자동 갱신: `certbot renew` (systemd timer).

## 프론트 연결값
- 모바일: `EXPO_PUBLIC_API_URL=https://api.mediview.example.com` (WS 는 자동으로 `wss://…` 파생)
- 관리자: `NEXT_PUBLIC_API_URL=https://api.mediview.example.com`

## 참고: 모바일 WebSocket 과 allowedOrigin
네이티브 앱의 WS 핸드셰이크는 브라우저 `Origin` 헤더가 없을 수 있습니다.
Spring 의 `cors.allowed-origin-patterns` 가 특정 도메인으로만 제한되면 앱 WS 가 거부될 수 있으니,
앱 트래픽은 JWT 핸드셰이크 인증으로 신뢰하고 WS 출처 제한은 웹(admin/landing) 도메인 기준으로 두세요.
