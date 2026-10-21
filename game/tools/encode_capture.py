#!/usr/bin/env python3
"""Encode timestamped engine JPEG samples without compressing gaps in time.
Video is silent; repeated frames retain the measured interval between samples.
"""
import argparse,json,subprocess,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('frames',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
rows=[json.loads(line) for line in (a.frames/'frames.jsonl').read_text().splitlines() if line.strip()]
assert len(rows)>1 and all(rows[i]['seconds']<rows[i+1]['seconds'] for i in range(len(rows)-1))
timeline=a.output.with_suffix('.ffconcat');lines=['ffconcat version 1.0']
def quoted(path):return "'"+str(path.resolve()).replace("'","'\\''")+"'"
for i,row in enumerate(rows):
 file=a.frames/row['file'];assert file.is_file()
 lines+=['file '+quoted(file),'option framerate 1000']
 if i+1<len(rows):lines+=['duration %.6f'%(rows[i+1]['seconds']-row['seconds'])]
lines+=['file '+quoted(a.frames/rows[-1]['file']),'option framerate 1000']
timeline.write_text('\n'.join(lines)+'\n')
subprocess.run(['ffmpeg','-hide_banner','-y','-f','concat','-safe','0','-i',str(timeline),'-an','-c:v','libx264','-preset','fast','-crf','22','-pix_fmt','yuv420p','-fps_mode','vfr','-movflags','+faststart',str(a.output)],check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','quiet','-print_format','json','-show_format','-show_streams',str(a.output)]))
report={'source':'actual Godot viewport readbacks','editing':'No cuts; frame durations follow monotonic capture timestamps','audio':'silent; no audio recorded','first_source_second':rows[0]['seconds'],'last_source_second':rows[-1]['seconds'],'sample_count':len(rows),'expected_duration_seconds':rows[-1]['seconds']-rows[0]['seconds'],'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'probe':probe}
a.output.with_suffix('.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:report[k] for k in ['sample_count','expected_duration_seconds','sha256']}))
