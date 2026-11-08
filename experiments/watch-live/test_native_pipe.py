import os, tempfile, struct, unittest
from live_receiver import NativePipe
class NativePipeTests(unittest.TestCase):
 def test_framed_pcm_and_clean_end(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600)
   rd=os.open(p,os.O_RDONLY|os.O_NONBLOCK)
   try:
    native=NativePipe(p)
    native.send(b"\x01\x00\xff\x7f")
    native.finish()
    self.assertEqual(os.read(rd,100),struct.pack(">I",4)+b"\x01\x00\xff\x7f"+b"\0"*4)
    with self.assertRaises(OSError):native.send(b"\0\0")
   finally:os.close(rd)
 def test_wrong_permissions_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600);os.chmod(p,0o644)
   rd=os.open(p,os.O_RDONLY|os.O_NONBLOCK)
   try:
    with self.assertRaises(ValueError):NativePipe(p)
   finally:os.close(rd)
 def test_no_reader_and_symlink_fail(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600)
   with self.assertRaises(OSError):NativePipe(p)
   link=d+"/link";os.symlink(p,link)
   with self.assertRaises(OSError):NativePipe(link)
 def test_disconnected_reader_fails(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600)
   rd=os.open(p,os.O_RDONLY|os.O_NONBLOCK);native=NativePipe(p);os.close(rd)
   try:
    with self.assertRaises(OSError):native.send(b"\0\0")
   finally:native.close()
if __name__=="__main__":unittest.main()
