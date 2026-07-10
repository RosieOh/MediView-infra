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
| `compose.yaml` | mariadb·backend·ai·landing·admin·nginx·certbot·coturn 통합 실행 |
| `stack/nginx.conf` | compose 서비스명 기반 리버스 프록시 |
| `.env.example` | DB·JWT·암호화키·TURN·CORS 시크릿 템플릿 |
| `init-letsencrypt.sh` | Let's Encrypt 최초 인증서 발급 부트스트랩 |

## TLS (Let's Encrypt · certbot 자동 갱신)
`certbot` 컨테이너가 webroot(`/.well-known/acme-challenge/`) 방식으로 인증서를 발급/갱신하고,
`nginx` 는 6시간마다 reload 하여 갱신분을 반영합니다.

**최초 발급 (1회):**
```bash
# init-letsencrypt.sh 상단의 DOMAINS / EMAIL 을 실제 값으로 수정 (DNS 가 이 서버를 가리켜야 함)
chmod +x init-letsencrypt.sh
./init-letsencrypt.sh
```
이후 갱신은 `certbot` 컨테이너가 12시간 주기로 자동 수행합니다. (스테이징 테스트: 스크립트의 `STAGING=1`)

## 배포 자동화 (`.github/workflows/deploy.yml`)
`Actions → deploy → Run workflow` 로 서버에 SSH 접속해 GHCR 로그인 후 `pull && up -d` 합니다.

필요한 Secrets:
| Secret | 용도 |
|--------|------|
| `DEPLOY_HOST` / `DEPLOY_USER` / `DEPLOY_SSH_KEY` / `DEPLOY_PATH` | SSH 접속 및 배포 경로 |
| `GHCR_USER` | GHCR 사용자명(=GitHub 계정) |
| `GHCR_TOKEN` | `read:packages` 권한 PAT (private 이미지 pull 용) |

### GHCR 이미지 접근 (private vs public)
CI 가 만든 이미지는 기본 **private** 입니다. 배포 서버가 pull 하려면 둘 중 하나:
- **(권장) 인증 pull** — 위 `GHCR_USER`/`GHCR_TOKEN` 으로 서버가 `docker login ghcr.io` (deploy.yml 이 자동 처리).
- **public 전환** — GitHub 각 패키지 → Package settings → Change visibility → Public (패키지당 1회).
  사용자 소유 컨테이너 패키지는 REST API 로 자동 전환이 지원되지 않아 UI 에서 수동 설정합니다.
