import argparse
import json
import statistics
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests


_thread_local = threading.local()


def parse_json_value(value: str) -> Dict[str, Any]:
    if not value:
        return {}
    if value.startswith('@'):
        path = Path(value[1:])
        return json.loads(path.read_text(encoding='utf-8'))
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError('payload json must be an object')
    return parsed


def percentile(values: List[float], percent: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * percent / 100.0))
    return ordered[max(0, min(index, len(ordered) - 1))]


def get_session() -> requests.Session:
    session = getattr(_thread_local, 'session', None)
    if session is None:
        session = requests.Session()
        _thread_local.session = session
    return session


def login(base_url: str, username: str, password: str, timeout: float) -> str:
    response = requests.post(
        f'{base_url}/api/auth/login',
        json={'username': username, 'password': password},
        timeout=timeout,
    )
    response.raise_for_status()
    body = response.json()
    token = body.get('token')
    if not token:
        raise RuntimeError('login response missing token')
    return token


def build_request_body(args: argparse.Namespace, sequence: int) -> Dict[str, Any]:
    body: Dict[str, Any] = {
        'timeoutSeconds': args.timeout_seconds,
        'payload': dict(args.payload),
    }
    if args.client_id:
        body['clientId'] = args.client_id
    if args.auth == 'body':
        body['username'] = args.username
        body['password'] = args.password
    if args.include_sequence:
        payload = body.setdefault('payload', {})
        payload['_perfSeq'] = sequence
    return body


def invoke_once(args: argparse.Namespace, token: str, sequence: int) -> Dict[str, Any]:
    session = get_session()
    headers = {'Content-Type': 'application/json'}
    if args.auth == 'bearer':
        headers['Authorization'] = f'Bearer {token}'

    url = f'{args.base_url}/rpc/invoke/{args.group}/{args.action}'
    body = build_request_body(args, sequence)
    started = time.perf_counter()
    try:
        response = session.post(url, headers=headers, json=body, timeout=args.http_timeout)
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        text = response.text
        try:
            data = response.json()
        except ValueError:
            data = {}

        status = str(data.get('status') or f'http_{response.status_code}')
        is_ok = data.get('is_ok')
        if is_ok is None:
            is_ok = response.ok and status == 'success'
        return {
            'ok': bool(is_ok),
            'http_code': response.status_code,
            'status': status,
            'elapsed_ms': elapsed_ms,
            'server_latency_ms': float(data.get('latencyMs') or 0),
            'error': str(data.get('error') or '')[:300],
            'body': text[:500],
        }
    except Exception as exc:
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        return {
            'ok': False,
            'http_code': 0,
            'status': 'client_error',
            'elapsed_ms': elapsed_ms,
            'server_latency_ms': 0.0,
            'error': str(exc)[:300],
            'body': '',
        }


def run_round(args: argparse.Namespace, token: str, total: int, label: str) -> List[Dict[str, Any]]:
    if total <= 0:
        return []

    print(f'{label}: total={total}, concurrency={args.concurrency}')
    started = time.perf_counter()
    results: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [executor.submit(invoke_once, args, token, index) for index in range(total)]
        for future in as_completed(futures):
            results.append(future.result())
            if args.progress and len(results) % args.progress == 0:
                print(f'  completed {len(results)}/{total}')
    elapsed = time.perf_counter() - started
    print(f'{label} finished in {elapsed:.2f}s')
    return results


def print_report(results: List[Dict[str, Any]], elapsed_seconds: float, max_errors: int) -> None:
    total = len(results)
    ok_count = sum(1 for item in results if item['ok'])
    failed_count = total - ok_count
    status_counter = Counter(str(item['status']) for item in results)
    http_counter = Counter(str(item['http_code']) for item in results)
    elapsed_values = [float(item['elapsed_ms']) for item in results]
    server_values = [float(item['server_latency_ms']) for item in results if float(item['server_latency_ms']) > 0]
    rps = total / elapsed_seconds if elapsed_seconds > 0 else 0.0
    success_rate = ok_count * 100.0 / total if total else 0.0

    print('')
    print('=== r0rpc performance report ===')
    print(f'total requests : {total}')
    print(f'success        : {ok_count}')
    print(f'failed         : {failed_count}')
    print(f'success rate   : {success_rate:.2f}%')
    print(f'total time     : {elapsed_seconds:.2f}s')
    print(f'throughput     : {rps:.2f} req/s')
    print('')
    print('client observed latency:')
    print(f'  avg          : {statistics.mean(elapsed_values):.2f} ms' if elapsed_values else '  avg          : 0.00 ms')
    print(f'  p50          : {percentile(elapsed_values, 50):.2f} ms')
    print(f'  p90          : {percentile(elapsed_values, 90):.2f} ms')
    print(f'  p95          : {percentile(elapsed_values, 95):.2f} ms')
    print(f'  p99          : {percentile(elapsed_values, 99):.2f} ms')
    print(f'  max          : {max(elapsed_values):.2f} ms' if elapsed_values else '  max          : 0.00 ms')

    if server_values:
        print('')
        print('server reported latency:')
        print(f'  avg          : {statistics.mean(server_values):.2f} ms')
        print(f'  p95          : {percentile(server_values, 95):.2f} ms')
        print(f'  max          : {max(server_values):.2f} ms')

    print('')
    print('status distribution:')
    for status, count in status_counter.most_common():
        print(f'  {status:<16} {count}')

    print('')
    print('http distribution:')
    for code, count in http_counter.most_common():
        print(f'  {code:<16} {count}')

    errors = [item for item in results if item.get('error')]
    if max_errors > 0 and errors:
        print('')
        print('sample errors:')
        for item in errors[:max_errors]:
            print(f"  status={item['status']} http={item['http_code']} error={item['error']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Run HTTP invoke performance test for r0rpc.')
    parser.add_argument('--base-url', default='http://127.0.0.1:9876', help='server base url')
    parser.add_argument('--username', default='admin', help='admin username')
    parser.add_argument('--password', default='123456', help='admin password')
    parser.add_argument('--group', default='idlefish', help='target group')
    parser.add_argument('--action', default='ping', help='target action')
    parser.add_argument('--client-id', default='', help='optional fixed client id')
    parser.add_argument('--requests', type=int, default=1000, help='total request count')
    parser.add_argument('--concurrency', type=int, default=50, help='parallel worker count')
    parser.add_argument('--timeout-seconds', type=int, default=20, help='rpc timeoutSeconds')
    parser.add_argument('--http-timeout', type=float, default=30.0, help='HTTP client timeout seconds')
    parser.add_argument('--payload-json', default='{}', help='payload JSON object, or @file.json')
    parser.add_argument('--auth', choices=['bearer', 'body', 'none'], default='bearer', help='invoke auth mode')
    parser.add_argument('--warmup', type=int, default=0, help='warmup request count before measured run')
    parser.add_argument('--progress', type=int, default=0, help='print progress every N completed requests')
    parser.add_argument('--print-errors', type=int, default=5, help='print up to N sample errors')
    parser.add_argument('--include-sequence', action='store_true', help='append _perfSeq to payload')
    args = parser.parse_args()

    args.base_url = args.base_url.rstrip('/')
    if args.requests <= 0:
        raise SystemExit('--requests must be greater than 0')
    if args.concurrency <= 0:
        raise SystemExit('--concurrency must be greater than 0')
    args.payload = parse_json_value(args.payload_json)
    return args


def main() -> None:
    args = parse_args()
    token = ''
    if args.auth == 'bearer':
        print('login...')
        token = login(args.base_url, args.username, args.password, args.http_timeout)

    if args.warmup > 0:
        run_round(args, token, args.warmup, 'warmup')

    started = time.perf_counter()
    results = run_round(args, token, args.requests, 'benchmark')
    elapsed = time.perf_counter() - started
    print_report(results, elapsed, args.print_errors)


if __name__ == '__main__':
    main()
