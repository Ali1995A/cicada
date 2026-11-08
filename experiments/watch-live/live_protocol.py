"""Experimental live PCM transport. No transcription and no persistent audio storage."""
import io
import re
import time
import wave
from urllib.parse import urlsplit
MAX_BYTES = 128000  # Four seconds, mono signed PCM16LE at 16 kHz.
class ProtocolError(ValueError): pass

def validate_endpoint(url):
    p = urlsplit(url)
    local = p.hostname in ("localhost", "127.0.0.1", "::1")
    if not p.hostname or p.username or p.password or p.query or p.fragment:
        raise ValueError("Use a plain endpoint, without credentials, query or fragment")
    if p.scheme != "https" and not (p.scheme == "http" and local):
        raise ValueError("HTTPS is required outside loopback")
    return url

def validate_frame(body):
    if not 0 < len(body) <= MAX_BYTES or len(body) % 2:
        raise ProtocolError("Invalid PCM length")

def wav_bytes(body):
    validate_frame(body)
    out = io.BytesIO()
    with wave.open(out, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000)
        f.writeframes(body)
    return out.getvalue()

class Session:
    def __init__(self, identifier, now=None):
        if not re.fullmatch(r"[a-f0-9]{32}", identifier):
            raise ProtocolError("Invalid session")
        self.identifier = identifier
        self.next_sequence = 0
        self.last_seen = time.monotonic() if now is None else now

    def accept(self, identifier, sequence, body, now=None):
        now = time.monotonic() if now is None else now
        if now - self.last_seen > 30:
            raise ProtocolError("Session expired; start a new recording")
        if identifier != self.identifier or sequence != self.next_sequence:
            raise ProtocolError("Session or sequence mismatch; audio gap")
        validate_frame(body)
        self.next_sequence += 1
        self.last_seen = now
