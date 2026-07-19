#!/usr/bin/env python3
"""
Rate limit smoke test — hits the `rate-limit-test` mock model (rpm_limit=3).
No Azure calls are made; mock_response returns immediately.
Expects: first 3 requests pass (200), requests 4-6 get rate-limited (429).

Usage:
    LITELLM_URL=<gateway-fqdn> LITELLM_MASTER_KEY=<key> python eval/test_rate_limits.py
"""
import os
import sys
import httpx

GATEWAY_URL = os.environ["LITELLM_URL"]
MASTER_KEY = os.environ["LITELLM_MASTER_KEY"]
MODEL = "rate-limit-test"
TOTAL_REQUESTS = 6
EXPECTED_PASS = 3


def send_request(client: httpx.Client, idx: int) -> tuple[int, str]:
    resp = client.post(
        f"https://{GATEWAY_URL}/v1/chat/completions",
        headers={"Authorization": f"Bearer {MASTER_KEY}"},
        json={
            "model": MODEL,
            "messages": [{"role": "user", "content": "ping"}],
        },
        timeout=10,
    )
    return resp.status_code, resp.text


def main():
    passed = 0
    limited = 0

    with httpx.Client() as client:
        for i in range(1, TOTAL_REQUESTS + 1):
            status, body = send_request(client, i)
            if status == 200:
                passed += 1
                print(f"Request {i}: PASS (200)")
            elif status == 429:
                limited += 1
                print(f"Request {i}: RATE LIMITED (429)")
            else:
                print(f"Request {i}: UNEXPECTED {status} — {body[:200]}")

    print(f"\nPassed: {passed}  Rate-limited: {limited}")

    if passed > EXPECTED_PASS:
        print(f"FAIL — expected at most {EXPECTED_PASS} to pass, got {passed}. RPM limit not enforced.")
        sys.exit(1)
    if limited == 0:
        print("FAIL — no requests were rate-limited. RPM limit not enforced.")
        sys.exit(1)

    print(f"PASS — RPM limit of {EXPECTED_PASS} is enforced correctly.")


if __name__ == "__main__":
    main()
