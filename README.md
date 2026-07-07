# MediView 배포 인프라

MediView 스택의 배포/인프라 설정 모음.

| 디렉터리 | 내용 |
|----------|------|
| `coturn/` | WebRTC 미디어 릴레이(TURN/STUN). docker-compose + turnserver.conf |
| `nginx/`  | 리버스 프록시(api/ws 라우팅, WS 업그레이드, TLS/certbot) |

## 연동 개요
```
mobile/admin/landing ─▶ [nginx :443 TLS] ─▶ Spring :8080 (MediView 백엔드)
화상 통화 미디어 ─▶ [coturn :3478/udp, 49160-49200] (P2P 실패 시 릴레이)
```
- 백엔드(RosieOh/MediView)의 `GET /api/webrtc/ice` 가 coturn `static-auth-secret` 으로 단기 TURN 자격증명을 발급합니다.
- **coturn `TURN_SECRET` 과 백엔드 `turn.static-auth-secret` 은 반드시 동일해야 합니다.**

각 디렉터리의 README 를 참고해 값을 채우고 배포하세요.

## 전체 스택 (docker-compose)
`compose.yaml` 는 DB·백엔드·AI·프론트(admin/landing)·nginx·coturn 을 한 번에 띄웁니다.
앱 이미지는 각 저장소 CI 가 `ghcr.io/rosieoh/mediview-*` 로 푸시합니다.

```bash
cp .env.example .env      # 시크릿/도메인 채우기
docker compose pull
docker compose up -d
```

| 파일 | 용도 |
|------|------|
| `compose.yaml` | mariadb·backend·ai·landing·admin·nginx·coturn 통합 실행 |
| `stack/nginx.conf` | compose 서비스명 기반 리버스 프록시 |
| `.env.example` | DB·JWT·암호화키·TURN·CORS 시크릿 템플릿 |

### 배포 자동화 (`.github/workflows/deploy.yml`)
`Actions → deploy → Run workflow` 로 서버에 SSH 접속해 `pull && up -d` 합니다.
필요한 Secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`.

> TLS: `./certs/{fullchain,privkey}.pem` 를 마운트하거나 certbot 컨테이너를 추가하세요.
