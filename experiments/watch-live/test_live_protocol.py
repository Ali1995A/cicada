import io, unittest, wave
from live_protocol import validate_endpoint, validate_frame, Session, ProtocolError, wav_bytes
class ProtocolTests(unittest.TestCase):
 def test_endpoint_rejects_cleartext_remote_and_embedded_secrets(self):
  for u in ["http://example.com/v1/audio/transcriptions", "https://u:p@example.com/a", "https://example.com/a?key=x", "https://example.com/a#x"]:
   with self.assertRaises(ValueError): validate_endpoint(u)
  self.assertEqual(validate_endpoint("http://127.0.0.1:8080/v1/audio/transcriptions"), "http://127.0.0.1:8080/v1/audio/transcriptions")
 def test_frame_bounds(self):
  for body in [b"", b"x", b"x"*128002]:
   with self.assertRaises(ProtocolError): validate_frame(body)
  validate_frame(b"\0"*128000)
 def test_wav(self):
  with wave.open(io.BytesIO(wav_bytes(b"\0"*32000))) as f:
   self.assertEqual((f.getframerate(), f.getnchannels(), f.getsampwidth(), f.getnframes()), (16000,1,2,16000))
 def test_sequence_and_expiry(self):
  s=Session("a"*32, now=0)
  s.accept("a"*32,0,b"\0\0",now=1)
  for session, seq, now in [("b"*32,1,2),("a"*32,0,2),("a"*32,2,2),("a"*32,1,32)]:
   with self.assertRaises(ProtocolError): s.accept(session,seq,b"\0\0",now=now)
 def test_invalid_frame_does_not_advance(self):
  s=Session("a"*32, now=0)
  with self.assertRaises(ProtocolError): s.accept("a"*32,0,b"x",now=1)
  s.accept("a"*32,0,b"\0\0",now=1)
if __name__=="__main__": unittest.main()
