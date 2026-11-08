#!/usr/bin/env python3
"""Experimental Watch -> Mac live transport probe. NOT the Cicada recognizer.
Run explicitly with a certificate trusted by the Watch. No TLS bypass.
Only prints frame metadata; audio and tokens are never written to disk.
"""
import argparse
import hmac
import json
import math
import re
import secrets
import ssl
import struct
import time
import os
import tempfile
import stat
import select
from http.server import BaseHTTPRequestHandler, HTTPServer
from live_protocol import Session, ProtocolError, MAX_BYTES

class Receiver(HTTPServer):
    allow_reuse_address = True
    def __init__(self, address, token, on_frame, native=None):
        if not re.fullmatch(r"[a-f0-9]{64}", token):
            raise ValueError("Pairing token must be 32 random bytes in hex")
        self.token, self.on_frame, self.session = token, on_frame, None
        self.native = native
        self.bridge_finished = False
        super().__init__(address, Handler)
    def get_request(self):
        sock, address = super().get_request()
        sock.settimeout(5)
        return sock, address

class Handler(BaseHTTPRequestHandler):
    # Close each response: no indefinite client monopolizing a single-user probe.
    protocol_version = "HTTP/1.0"
    def log_message(self, *args): pass
    def reply(self, status, payload):
        data=json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(data)))
        self.send_header("Cache-Control","no-store")
        self.end_headers()
        self.wfile.write(data)
    def do_POST(self):
        try:
            self.handle_post()
        except (TimeoutError, ConnectionError, BrokenPipeError):
            self.close_connection = True
    def handle_post(self):
        auth=self.headers.get("Authorization","")
        if not hmac.compare_digest(auth.encode("utf-8"), ("Bearer "+self.server.token).encode("ascii")):
            self.reply(401,{"error":"Unauthorized"});return
        if self.headers.get("Transfer-Encoding"):
            self.reply(400,{"error":"Content-Length required"});return
        length=self.headers.get("Content-Length","")
        if not length.isascii() or not length.isdecimal() or len(length) > 6:
            self.reply(400,{"error":"Invalid length"});return
        length=int(length)
        if length > MAX_BYTES:
            self.reply(413,{"error":"Frame too large"});return
        body=self.rfile.read(length)
        if len(body)!=length:
            self.reply(400,{"error":"Truncated frame"});return
        current=self.server.session
        if self.path == "/session":
            if self.server.bridge_finished:
                self.reply(409,{"error":"Native bridge ended; restart receiver and meeting"});return
            if body:
                self.reply(400,{"error":"Session request must be empty"});return
            if current and time.monotonic()-current.last_seen <=30:
                self.reply(409,{"error":"Already recording"});return
            current=Session(secrets.token_hex(16))
            self.server.session=current
            self.reply(201,{"session":current.identifier,"sample_rate":16000,"max_seconds":4});return
        end=re.fullmatch(r"/end/([a-f0-9]{32})",self.path)
        if end:
            if current and current.identifier==end[1]:
                if self.server.native:
                    try: self.server.native.finish()
                    except (OSError, TimeoutError):
                        self.server.bridge_finished=True
                        self.reply(503,{"error":"Native receiver disconnected"});return
                    self.server.bridge_finished=True
                self.server.session=None
                self.reply(200,{"ended":True})
            else: self.reply(409,{"error":"Unknown session"})
            return
        frame=re.fullmatch(r"/pcm/([a-f0-9]{32})/([0-9]{1,10})",self.path)
        if not frame:
            self.reply(404,{"error":"Unknown path"});return
        if not current:
            self.reply(409,{"error":"Start a session"});return
        try:
            current.accept(frame[1],int(frame[2]),body)
        except ProtocolError as e:
            self.reply(400 if "length" in str(e) else 409,{"error":str(e)});return
        if self.server.native:
            try: self.server.native.send(body)
            except (OSError, TimeoutError):
                self.server.native.close()
                self.server.bridge_finished=True
                self.reply(503,{"error":"Native receiver disconnected or overloaded"});return
        samples=len(body)//2
        power=sum(x[0]*x[0] for x in struct.iter_unpack("<h",body))/samples
        event={"sequence":int(frame[2]),"samples":samples,"seconds":samples/16000,
               "rms":math.sqrt(power)/32768,"received_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())}
        self.server.on_frame(event)
        self.reply(200,{"accepted":int(frame[2]),"seconds":samples/16000})

class NativePipe:
    """Private, same-user FIFO bridge. No filesystem audio retention."""
    def __init__(self, path):
        self.fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        info = os.fstat(self.fd)
        if not stat.S_ISFIFO(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            self.close()
            raise ValueError("Native FIFO must be owned by this user with mode 0600")
    def send(self, pcm):
        from live_protocol import validate_frame
        validate_frame(pcm)
        self._write(struct.pack(">I",len(pcm))+pcm)
    def _write(self, data):
        deadline=time.monotonic()+5
        while data:
            if self.fd < 0: raise OSError("Native bridge is closed")
            remaining=deadline-time.monotonic()
            if remaining <=0: raise TimeoutError("Native bridge backlog")
            _,ready,_=select.select([], [self.fd], [], remaining)
            if not ready: raise TimeoutError("Native bridge backlog")
            try: n=os.write(self.fd,data)
            except BlockingIOError: continue
            if n <=0: raise OSError("Native bridge disconnected")
            data=data[n:]
    def finish(self):
        try: self._write(b"\0"*4)
        finally: self.close()
    def close(self):
        if self.fd >= 0:
            os.close(self.fd);self.fd=-1

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bind", default="127.0.0.1")
    p.add_argument("--port", type=int,default=8443)
    p.add_argument("--cert",required=True)
    p.add_argument("--key",required=True)
    p.add_argument("--native-fifo",help="Opt in to feeding an already-running Cicada DEBUG room input")
    args=p.parse_args()
    token=secrets.token_hex(32)
    native=NativePipe(args.native_fifo) if args.native_fifo else None
    server=Receiver((args.bind,args.port),token,lambda e:print(json.dumps(e),flush=True), native=native)
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version=ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(args.cert,args.key)
    # Handshake is performed with a timeout in get_request, not during accept.
    original=server.get_request
    def tls_request():
        sock,address=original()
        try: return ctx.wrap_socket(sock,server_side=True),address
        except Exception:
            sock.close();raise
    server.get_request=tls_request
    fd, token_path = tempfile.mkstemp(prefix="cicada-watch-pair-", suffix=".txt")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as f: f.write(token)
        print("EXPERIMENTAL: "+("feeding Cicada native recognition" if native else "transport metadata only"), flush=True)
        print("Read the private 0600 pairing file locally; do not share: "+token_path, flush=True)
        try: server.serve_forever()
        except KeyboardInterrupt: pass
    finally:
        server.server_close()
        if native: native.close()
        os.unlink(token_path)
if __name__=="__main__": main()
