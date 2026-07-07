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
