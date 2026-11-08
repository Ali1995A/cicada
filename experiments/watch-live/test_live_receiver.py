import http.client, json, threading, unittest, os, tempfile, struct
from live_receiver import NativePipe
from live_receiver import Receiver
class ReceiverTests(unittest.TestCase):
 def setUp(self):
  self.events=[]
  self.s=Receiver(("127.0.0.1",0),"a"*64,self.events.append)
  self.t=threading.Thread(target=self.s.serve_forever,daemon=True); self.t.start()
 def tearDown(self):
  self.s.shutdown();self.s.server_close();self.t.join()
 def post(self,path,body=b"",token="a"*64):
  c=http.client.HTTPConnection(*self.s.server_address,timeout=2)
  c.request("POST",path,body,{"Authorization":"Bearer "+token,"Content-Type":"application/octet-stream"})
  r=c.getresponse();result=(r.status,json.loads(r.read()));c.close();return result
 def test_auth_and_sequencing(self):
  self.assertEqual(self.post("/session",token="bad")[0],401)
  code,j=self.post("/session");self.assertEqual(code,201);sid=j["session"]
  self.assertEqual(self.post("/session")[0],409)
  path="/pcm/"+sid+"/0"
  self.assertEqual(self.post(path,b"\0"*64000)[0],200)
  self.assertEqual(len(self.events),1)
  self.assertEqual(self.events[0]["samples"],32000)
  self.assertEqual(self.post(path,b"\0"*64000)[0],409)
  self.assertEqual(self.post("/end/"+sid)[0],200)
 def test_non_ascii_auth_is_rejected(self):
  self.assertEqual(self.post("/session",token="é")[0],401)
 def test_malformed_does_not_emit(self):
  _,j=self.post("/session");sid=j["session"]
  self.assertEqual(self.post("/pcm/"+sid+"/0",b"x")[0],400)
  self.assertEqual(self.events,[])
  self.assertEqual(self.post("/pcm/"+sid+"/0",b"\0\0")[0],200)
 def test_http_audio_reaches_native_fifo_before_ack(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600)
   rd=os.open(p,os.O_RDONLY|os.O_NONBLOCK)
   native=NativePipe(p);self.s.native=native
   try:
    _,j=self.post("/session");sid=j["session"]
    self.assertEqual(self.post("/pcm/"+sid+"/0",b"\x01\x00")[0],200)
    self.assertEqual(os.read(rd,99),struct.pack(">I",2)+b"\x01\x00")
    self.assertEqual(self.post("/end/"+sid)[0],200)
    self.assertEqual(os.read(rd,99),b"\0"*4)
    self.assertEqual(self.post("/session")[0],409)
   finally:native.close();os.close(rd)
 def test_native_disconnect_is_visible_http_failure(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+"/audio";os.mkfifo(p,0o600)
   rd=os.open(p,os.O_RDONLY|os.O_NONBLOCK);native=NativePipe(p);self.s.native=native
   os.close(rd)
   try:
    _,j=self.post("/session");sid=j["session"]
    self.assertEqual(self.post("/pcm/"+sid+"/0",b"\0\0")[0],503)
    self.assertEqual(self.post("/session")[0],409)
   finally:native.close()
 def test_pathological_content_length(self):
  c=http.client.HTTPConnection(*self.s.server_address,timeout=2)
  c.request("POST","/session",b"",{"Authorization":"Bearer "+"a"*64,"Content-Length":"9"*5000})
  r=c.getresponse();self.assertEqual(r.status,400);r.read();c.close()
 def test_oversize_and_wrong_path(self):
  c=http.client.HTTPConnection(*self.s.server_address,timeout=2)
  try:
   # Header-only rejection must not depend on TCP accepting a body the server refuses.
   c.putrequest("POST","/session")
   c.putheader("Authorization","Bearer "+"a"*64)
   c.putheader("Content-Length","128001")
   c.endheaders()
   r=c.getresponse();self.assertEqual(r.status,413);r.read()
  finally:c.close()
  self.assertEqual(self.post("/not-real")[0],404)
if __name__=="__main__": unittest.main()
