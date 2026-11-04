#!/usr/bin/env python3
"""Webhook sink for alertmanager_test: records every POST body.

  webhook_sink.py <dir> <port_file>

Listens on a free 127.0.0.1 port, writes the port to <port_file> once
listening, and saves each request body as <dir>/<n>.json (n = 1, 2, ...,
written via tmp + rename so readers never see a partial file).
"""

import http.server
import os
import sys
import threading

_lock = threading.Lock()
_count = [0]


def main(out_dir, port_file):
    os.makedirs(out_dir, exist_ok=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            with _lock:
                _count[0] += 1
                path = os.path.join(out_dir, f"{_count[0]}.json")
            with open(path + ".tmp", "wb") as f:
                f.write(body)
            os.replace(path + ".tmp", path)
            self.send_response(200)
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(port_file + ".tmp", "w") as f:
        f.write(str(server.server_address[1]))
    os.replace(port_file + ".tmp", port_file)
    server.serve_forever()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
