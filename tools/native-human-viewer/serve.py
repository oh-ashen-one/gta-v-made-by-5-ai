"""Local-only review of the real private GLB. Install pinned npm dependencies first."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import argparse
root=Path(__file__).resolve().parent
model=root.parents[1]/'game/assets/providers/mixamo_josh/player_native.glb'
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(root),**kwargs)
 def do_GET(self):
  if self.path=='/player_native.glb':
   if not model.is_file():self.send_error(404,'Restore the licensed Mixamo asset first');return
   self.send_response(200);self.send_header('Content-Type','model/gltf-binary');self.send_header('Content-Length',str(model.stat().st_size));self.end_headers()
   with model.open('rb') as source:
    while data:=source.read(1024*1024):self.wfile.write(data)
  else:super().do_GET()
a=argparse.ArgumentParser();a.add_argument('--port',type=int,default=8793);args=a.parse_args()
ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
