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

## 모니터링 / 로그 (Prometheus · Grafana · Loki)
`monitoring/compose.monitoring.yml` 를 오버레이로 얹어 관측 스택을 띄웁니다.
```bash
docker compose -f compose.yaml -f monitoring/compose.monitoring.yml up -d
```
| 구성 | 역할 |
|------|------|
| Prometheus | 메트릭 수집(cAdvisor·node-exporter·백엔드 actuator) |
| Grafana | 대시보드 (`127.0.0.1:3300`, Prometheus·Loki 데이터소스 자동 프로비저닝) |
| Loki + Promtail | 전 컨테이너 로그 수집/조회 |
| cAdvisor / node-exporter | 컨테이너 / 호스트 메트릭 |

- Grafana 접속: `http://127.0.0.1:3300` (초기 admin 비번 `GRAFANA_ADMIN_PASSWORD`). 외부 노출은 nginx 서브도메인으로 프록시하세요.
- 백엔드 메트릭은 actuator + `micrometer-registry-prometheus` 로 수집됩니다 (백엔드에 반영 완료).

### 기본 대시보드 (자동 로드)
Grafana 실행 시 `MediView` 폴더에 다음 대시보드가 자동 프로비저닝됩니다.
| 대시보드 | 내용 |
|----------|------|
| **MediView · JVM / App** | Heap, HTTP req/s, GC, 스레드, CPU (micrometer) |
| **MediView · Containers** | 컨테이너 CPU/메모리/네트워크 (cAdvisor) |
| **MediView · Business** | 사용자/예약/상담 수, 결제 성공률·상태 (백엔드 커스텀 게이지) |

### 알림 (Alertmanager · Slack/이메일)
Prometheus 규칙(`monitoring/prometheus/alerts.yml`) 위반 시 Alertmanager 가 Slack/이메일로 알립니다.
기본 규칙: 타겟/백엔드 다운, 컨테이너 CPU 과다, JVM heap 90%+, 5xx 비율 5%+.

**설정 (비밀값은 파일로 주입, 커밋 제외):**
```bash
# Slack Webhook URL / SMTP 비밀번호를 secrets 파일로
echo 'https://hooks.slack.com/services/…' > monitoring/alertmanager/secrets/slack_url
echo 'smtp-password'                       > monitoring/alertmanager/secrets/smtp_password
# monitoring/alertmanager/alertmanager.yml 의 도메인/채널/수신자도 실제 값으로 수정
```
비-비밀 항목(smtp_smarthost, from, 채널 `#mediview-alerts`, 수신자)은 `alertmanager.yml` 에서 수정하세요.

### 로그 대시보드 / 에러 급증 알림 (Loki)
- 대시보드 **MediView · Logs (Loki)**: 서비스별 에러 rate·로그 volume·최근 에러 로그 뷰.
- Loki ruler(`monitoring/loki/rules/fake/rules.yml`)가 **에러 로그 급증**(5분 rate>1/s, 1분 20건+)을 감지해 Alertmanager 로 알립니다.

### 외부 URL/헬스 프로빙 (Blackbox exporter)
- `blackbox` 컨테이너 + Prometheus `blackbox-http` job 이 외부 도메인을 프로빙합니다.
- `monitoring/prometheus/prometheus.yml` 의 `targets` 를 실제 도메인으로 수정하세요.
- 알림: `ProbeDown`(프로빙 실패), `ProbeSslExpiringSoon`(인증서 14일 내 만료).

### Grafana 외부 노출 (nginx 서브도메인 + TLS)
`grafana.mediview.example.com` 을 nginx 로 프록시합니다(모니터링 오버레이가 nginx 에 conf 를 얹음).
1. DNS `grafana.*` → 서버, `init-letsencrypt.sh`(그라파나 도메인 포함) 로 인증서 발급.
2. `stack/nginx.grafana.conf` 의 도메인, `GRAFANA_ROOT_URL`(compose env) 을 실제 값으로 수정.
3. **이중 보호**: nginx basic-auth(외부 게이트) + Grafana 자체 로그인 + TLS.
   htpasswd 생성(커밋 금지): `htpasswd -cB monitoring/nginx-secrets/grafana.htpasswd admin`
   (Grafana 의 basic-auth 는 `GF_AUTH_BASIC_ENABLED=false` 로 꺼서 nginx basic-auth 와 충돌을 막습니다.)
4. `docker compose -f compose.yaml -f monitoring/compose.monitoring.yml up -d`

> **알림 노이즈 억제**: `alertmanager.yml` 에 inhibit_rules 적용 — 타겟 다운 시 그 인스턴스의 다른 알림 억제,
> 동일 알림에 critical 존재 시 warning 억제. 라우팅은 severity 별로 반복주기 분리(critical 1h / warning 6h).

## 스테이징 / 프로덕션 분리
베이스 `compose.yaml` + 환경별 오버레이 + `--env-file` 로 분리합니다. 이미지 태그는 `IMAGE_TAG` 로 제어합니다.

```bash
# 프로덕션
cp .env.production.example .env.production   # 값 채우기 (IMAGE_TAG=latest)
docker compose --env-file .env.production -f compose.yaml -f compose.prod.yml up -d

# 스테이징 (별도 호스트 권장 — coturn/nginx 포트 고정)
cp .env.staging.example .env.staging         # 값 채우기 (IMAGE_TAG=develop)
docker compose --env-file .env.staging -f compose.yaml -f compose.staging.yml up -d
```
- `compose.prod.yml` / `compose.staging.yml`: 로그 로테이션(json-file) + 프로젝트명 분리(`mediview` / `mediview-staging`).
- 실제 `.env.production` / `.env.staging` 는 `.gitignore` 로 커밋 제외(템플릿 `*.example` 만 커밋).

## 운영 (부하테스트 · SLO · 백업)

### 부하 테스트 (k6)
`loadtest/k6-smoke.js` + `Actions → loadtest → Run workflow`(BASE_URL 입력).
```bash
# 로컬 실행
k6 run -e BASE_URL=https://api.mediview.example.com -e TARGET_PATH=/actuator/health loadtest/k6-smoke.js
# 알림 실검증(에러 유발): -e FAULT=1  → 5xx 발생 → Http5xxElevated / ErrorBudgetBurn 발동 확인
```
임계값: p95 < 500ms, 에러율 < 1%. 주입 후 Grafana(JVM/Business)·Alertmanager 로 지표/알림 검증.

### SLO 에러버짓 번레이트 알림
가용성 SLO 99%(버짓 1%) 기준 **다중창 번레이트** 알림:
- `ErrorBudgetBurnFast` (5m+1h 창, ~14.4배) → critical(즉시 대응)
- `ErrorBudgetBurnSlow` (30m+6h 창, ~6배) → warning(원인 조사)

### mariadb 백업 (정기 덤프 + 보존)
`db-backup` 컨테이너가 **하루 1회** `mariadb-dump | gzip` 을 `./backups` 에 저장하고,
`BACKUP_RETENTION_DAYS`(기본 7) 초과분을 자동 삭제합니다.
```bash
# 수동 백업 1회
docker compose exec db-backup sh /usr/local/bin/backup.sh
# 복원
gunzip -c backups/mediview-YYYYmmdd-HHMMSS.sql.gz | \
  docker compose exec -T mariadb mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME"
```
> `./backups` 는 `.gitignore` 처리.

### 오프사이트 백업 (rclone → S3 등)
`offsite-backup` 서비스(프로파일 `offsite`)가 `./backups` 를 rclone 원격으로 6시간마다 동기화합니다.
```bash
cp backup/rclone.conf.example backup/rclone.conf   # 자격증명 입력(커밋 금지)
# .env 에 RCLONE_REMOTE=s3remote:mediview-backups
docker compose --profile offsite up -d offsite-backup
```

### 정기 스모크 (k6 스케줄)
`.github/workflows/smoke.yml` 이 6시간마다 k6 스모크를 실행합니다.
저장소 Variables 에 `LOADTEST_BASE_URL`(예: `https://api.mediview.example.com`)을 설정하면 활성화됩니다(미설정 시 스킵).

### 상태 페이지 / 업타임 (uptime-kuma)
모니터링 오버레이에 `uptime-kuma`(로컬 `127.0.0.1:3801`) 포함. 외부 노출은 nginx 서브도메인(status.*)으로 프록시 권장.
