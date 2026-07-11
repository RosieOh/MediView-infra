// MediView k6 부하/스모크 테스트.
// 실행: k6 run -e BASE_URL=https://api.mediview.example.com -e TARGET_PATH=/actuator/health loadtest/k6-smoke.js
// 알림 검증용(에러 유발): -e FAULT=1 로 존재하지 않는 경로도 함께 때려 5xx/4xx 를 만든다.
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const TARGET_PATH = __ENV.TARGET_PATH || "/actuator/health";
const FAULT = __ENV.FAULT === "1";

export const errorRate = new Rate("errors");

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 20 },
        { duration: "1m", target: 20 },
        { duration: "30s", target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<500"], // p95 < 500ms
    errors: ["rate<0.01"],            // 에러율 < 1%
  },
};

export default function () {
  const res = http.get(`${BASE_URL}${TARGET_PATH}`);
  const ok = check(res, { "status is 2xx": (r) => r.status >= 200 && r.status < 300 });
  errorRate.add(!ok);

  if (FAULT) {
    // 알림(5xx/4xx) 실검증용으로 의도적으로 없는 경로 호출
    http.get(`${BASE_URL}/__k6_fault_probe__`);
  }
  sleep(1);
}
