#!/usr/bin/env python3
"""Exercise policy semantics in an isolated Mihomo child process.

Only synthetic loopback HTTP proxies are used. They answer requests themselves;
no request is forwarded and no system proxy, user profile, or tunnel is changed.
JSON is used as valid YAML to avoid a Python YAML dependency.
"""

import argparse
import http.client
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FixtureProxy:
    def __init__(self, name):
        self.name = name
        self.available = True
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_CONNECT(self):
                if not fixture.available:
                    self.close_connection = True
                    return
                self.send_response(200, "Connection established")
                self.end_headers()
                self.close_connection = False
                self.handle_one_request()

            def do_HEAD(self):
                self.do_GET()

            def do_GET(self):
                if not fixture.available:
                    self.close_connection = True
                    return
                health = "/health" in self.path
                body = b"" if health else fixture.name.encode()
                self.send_response(204 if health else 200)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def log_message(self, *_):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def node(self):
        return {"name": self.name, "type": "http", "server": "127.0.0.1", "port": self.server.server_port}

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def available_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def request(port, target="same.example.invalid"):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        connection.request("GET", f"http://{target}/probe", headers={"Connection": "close"})
        response = connection.getresponse()
        data = response.read().decode()
        if response.status != 200 or data not in {"A", "B"}:
            raise RuntimeError(f"Unexpected fixture response: {response.status} {data!r}")
        return data
    finally:
        connection.close()


def wait_for(predicate, description, timeout=12):
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, http.client.HTTPException, RuntimeError) as error:
            last = error
        time.sleep(0.15)
    raise AssertionError(f"Timed out waiting for {description}; last error: {last}")


def run_case(binary, root, kind, strategy, first, second, generated_fixtures=None):
    port = available_port()
    group = {
        "name": "Policy", "type": kind, "proxies": ["A", "B"],
        "url": "http://fixture.invalid/health", "interval": 1, "lazy": False,
    }
    if strategy:
        group["strategy"] = strategy
    case = strategy or kind
    directory = root / case
    directory.mkdir()
    config = {
        "mixed-port": port, "allow-lan": False, "bind-address": "127.0.0.1",
        "mode": "rule", "log-level": "warning", "ipv6": False,
        "dns": {"enable": False}, "profile": {"store-selected": False},
        "proxies": [first.node(), second.node()], "proxy-groups": [group],
        "rules": ["MATCH,Policy"],
    }
    if generated_fixtures:
        # The caller converts Tower's YAML to JSON and supplies synthetic A/B
        # proxies, Policy group and MATCH rule. Retain the generated policy graph;
        # isolate listeners and endpoints so no native test can affect user traffic.
        generated = json.loads((generated_fixtures / f"{case}.json").read_text())
        if generated.get("proxy-providers") or generated.get("rule-providers"):
            raise ValueError("Generated runtime fixtures must not use remote providers")
        if generated.get("rules") != ["MATCH,Policy"]:
            raise ValueError("Generated runtime fixture must have only MATCH,Policy")
        nodes = generated.get("proxies", [])
        if len(nodes) != 2 or {node.get("name") for node in nodes} != {"A", "B"}:
            raise ValueError("Generated runtime fixture must contain exactly A and B")
        if any(node.get("type") != "http" or node.get("tls", False) is not False
               or set(node) - {"name", "type", "server", "port", "tls"} for node in nodes):
            raise ValueError("Generated runtime proxies must be bare HTTP nodes without credentials")
        groups = generated.get("proxy-groups", [])
        if any(group.get("use") or group.get("type") not in {"select", "url-test", "fallback", "load-balance"} for group in groups):
            raise ValueError("Unexpected external source or policy type in generated fixture")
        candidates = {"A", "B"} | {group.get("name") for group in groups}
        if any(not group.get("proxies") or any(name not in candidates for name in group["proxies"]) for group in groups):
            raise ValueError("Generated fixture members must refer only to A/B or declared groups; no DIRECT escape")
        policy = next((group for group in groups if group.get("name") == "Policy"), None)
        if not policy or policy.get("type") != kind or (strategy and policy.get("strategy") != strategy):
            raise ValueError("Generated Policy does not declare the expected semantics")
        for generated_group in groups:
            if generated_group.get("type") != "select":
                generated_group.update(url="http://fixture.invalid/health", interval=1, lazy=False)
        config["proxy-groups"] = groups
    path = directory / "config.json"
    path.write_text(json.dumps(config))
    check = subprocess.run([str(binary), "-t", "-f", str(path), "-d", str(directory)],
                           capture_output=True, text=True, timeout=15)
    if check.returncode:
        raise AssertionError(f"{case} checker rejected fixture: {check.stdout}\n{check.stderr}")
    first.available = second.available = True
    with (directory / "runtime.log").open("w") as output:
        process = subprocess.Popen([str(binary), "-f", str(path), "-d", str(directory)],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            wait_for(lambda: request(port), "isolated listener")
            if kind == "fallback":
                before = [request(port) for _ in range(4)]
                assert before == ["A"] * 4, f"fallback ignored member order: {before}"
                first.available = False
                wait_for(lambda: request(port) == "B", "fallback after first node fails")
                after = [request(port) for _ in range(4)]
                assert after == ["B"] * 4, f"fallback did not stay with available member: {after}"
                first.available = True
                wait_for(lambda: request(port) == "A", "fallback recovery to first member")
                detail = {"beforeFailure": before, "afterFailure": after, "recovered": "A"}
            elif strategy == "round-robin":
                labels = [request(port) for _ in range(10)]
                assert set(labels) == {"A", "B"}, f"round-robin did not distribute: {labels}"
                assert all(a != b for a, b in zip(labels, labels[1:])), f"not alternating: {labels}"
                detail = {"connections": labels}
            else:
                labels = [request(port) for _ in range(10)]
                assert len(set(labels)) == 1, f"same destination changed hash assignment: {labels}"
                # Each target uses a distinct registrable domain. Merely varying
                # subdomains cannot test Mihomo's eTLD+1 distribution.
                distributed = [request(port, f"fixture-{i}.invalid") for i in range(32)]
                assert set(distributed) == {"A", "B"}, "distinct targets never distributed"
                detail = {"sameDestination": labels[0], "distinctDestinationCounts": {
                    name: distributed.count(name) for name in ["A", "B"]}}
            return {"case": case, "checker": "passed", "runtime": "passed", "observed": detail}
        except Exception as error:
            raise AssertionError(f"{case}: {error}\n{(directory / 'runtime.log').read_text()}") from error
        finally:
            process.terminate()
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=4)
            first.available = second.available = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mihomo", type=Path, default=Path(".codex_work/release-43/tools/mihomo-darwin-arm64-v1.19.30"))
    parser.add_argument("--result", type=Path, help="Optional local JSON result path; no credentials recorded")
    parser.add_argument("--generated-fixtures", type=Path,
                        help="Tower output converted to JSON: fallback.json, round-robin.json, consistent-hashing.json; synthetic A/B nodes and Policy group")
    args = parser.parse_args()
    binary = args.mihomo.resolve()
    version = subprocess.run([str(binary), "-v"], capture_output=True, text=True, timeout=5, check=True).stdout.splitlines()[0]
    first, second = FixtureProxy("A"), FixtureProxy("B")
    try:
        with tempfile.TemporaryDirectory(prefix="tower-policy-runtime-") as temporary:
            results = [run_case(binary, Path(temporary), kind, strategy, first, second, args.generated_fixtures)
                       for kind, strategy in [("fallback", None), ("load-balance", "round-robin"),
                                              ("load-balance", "consistent-hashing")]]
        result = {"engine": version, "cases": results,
                  "scope": ("Supplied policy graph with isolated loopback endpoints and accelerated health checks; caller must establish fixture provenance."
                            if args.generated_fixtures else "Synthetic loopback Mihomo semantics only; not Tower-generated output or another client.")}
        rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
        if args.result:
            args.result.parent.mkdir(parents=True, exist_ok=True)
            args.result.write_text(rendered)
        print(rendered, end="")
    finally:
        first.close()
        second.close()


if __name__ == "__main__":
    main()
