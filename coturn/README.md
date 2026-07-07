# coturn (TURN/STUN)

화상 진료(WebRTC)에서 P2P 가 실패하는 네트워크(대칭 NAT, 기업/기관 방화벽, 셀룰러)를 위해
미디어를 릴레이하는 TURN 서버입니다. 백엔드가 `use-auth-secret` 방식으로 **단기 자격증명**을 발급합니다.

## 실행
```bash
cp .env.example .env      # EXTERNAL_IP / TURN_REALM / TURN_SECRET 채우기
docker compose up -d
docker compose logs -f coturn
```

## 방화벽/보안그룹에서 열어야 하는 포트
| 포트 | 프로토콜 | 용도 |
|------|----------|------|
| 3478 | UDP, TCP | STUN/TURN |
| 5349 | TCP | TURN over TLS (turns:) |
| 49160–49200 | UDP | 미디어 릴레이 범위 (turnserver.conf 와 일치) |

## 백엔드 연동 (중요)
`TURN_SECRET` 은 백엔드의 `turn.static-auth-secret` 과 **동일한 값**이어야 합니다.
백엔드는 `GET /api/webrtc/ice` 에서 이 시크릿으로 HMAC 서명한 단기 username/credential 을 발급하고,
클라이언트가 그 값으로 이 TURN 서버에 접속합니다. (자격증명이 코드/앱에 박히지 않습니다.)

## 동작 확인
https://icetest.info 또는 `trickle-ice` 페이지에서
`turn:turn.mediview.example.com:3478` + 발급된 username/credential 로 `relay` 후보가 나오면 정상입니다.
