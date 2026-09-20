#!/usr/bin/env python3
"""Import real Core Motion CSV into display-only evidence with an explicit reconstructed preview.

The input quaternion/rate/acceleration are recorded data. Original grip, neutral,
smoothing, game contact and racket output are unknown; never fabricate those as
historical evidence. The visualization uses the first quaternion as its reference.
"""
import argparse
import csv
import datetime as dt
import json
import math
from pathlib import Path
import statistics
import uuid


def quaternion(row):
    q = [float(row[f'q{k}']) for k in 'xyzw']
    length = math.sqrt(sum(x*x for x in q))
    if not math.isfinite(length) or length < .9 or length > 1.1:
        raise ValueError('invalid quaternion')
    return [x / length for x in q]


def multiply(a, b):
    x,y,z,w=a; X,Y,Z,W=b
    return [w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z]


def segments(path):
    segment=[]; source=None; previous=None
    with path.open() as stream:
        for row in csv.DictReader(stream):
            if not row.get('qx'):
                continue
            try:
                timestamp=float(row['received_uptime_s'])
                sensor=float(row['sensor_uptime_s'])
                quaternion(row)
                if row['mode'] != 'airpods' or row['source'] not in ('Left','Right'):
                    raise ValueError('not real AirPod data')
                if not math.isfinite(timestamp) or not math.isfinite(sensor):
                    raise ValueError('invalid time')
            except (ValueError, KeyError):
                if segment: yield segment
                segment=[]; source=None; previous=None
                continue
            if previous is not None and (row['source']!=source or timestamp<=previous or timestamp-previous>.25):
                if segment: yield segment
                segment=[]
            segment.append(row);source=row['source'];previous=timestamp
    if segment: yield segment


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='CSV file or directory containing airpods-*.csv')
    parser.add_argument('output', type=Path)
    args=parser.parse_args()
    files=[args.source] if args.source.is_file() else sorted(args.source.glob('airpods-*.csv'),reverse=True)
    chosen=None
    for path in files:
        if path.stat().st_size < 15000: continue
        for rows in segments(path):
            if float(rows[-1]['received_uptime_s'])-float(rows[0]['received_uptime_s'])<18: continue
            # Prefer a complete window with visible rotation rather than a static trace.
            for index in range(0,len(rows),300):
                start=float(rows[index]['received_uptime_s'])
                window=[]
                for row in rows[index:]:
                    if float(row['received_uptime_s'])-start>18:break
                    window.append(row)
                if len(window)<20 or float(window[-1]['received_uptime_s'])-start<17.8:continue
                first=quaternion(window[0])
                movement=max(1-abs(sum(a*b for a,b in zip(first,quaternion(r)))) for r in window)
                if chosen is None or movement>chosen[0]:chosen=(movement,path,window)
                if movement>.08:break
            if chosen and chosen[0]>.08:break
        if chosen and chosen[0]>.08:break
    if chosen is None:raise SystemExit('No continuous real same-source 18-second recording found')
    _,path,rows=chosen;first=quaternion(rows[0]);reference=[-first[0],-first[1],-first[2],first[3]]
    frequency=1/statistics.median(float(b['received_uptime_s'])-float(a['received_uptime_s']) for a,b in zip(rows,rows[1:]))
    frames=[];last=-math.inf
    for row in rows:
        time=float(row['received_uptime_s'])
        if time-last<.05:continue
        last=time;q=quaternion(row)
        def vector(prefix,suffix):return [float(row[f'{prefix}_{axis}_{suffix}']) for axis in 'xyz']
        frames.append(dict(capturedAt=time,receivedAt=time,sensorTime=float(row['sensor_uptime_s']),
            source=row['source'],reportedSource=row['source'],simulated=False,fresh=True,calibrated=False,
            quaternion=q,reference=first,basis=[0,0,0,1],racket=multiply(reference,q),
            eulerDegrees=[float(row[f'{name}_deg']) for name in ['yaw','pitch','roll']],
            angularVelocity=vector('rotation','rad_s'),userAcceleration=vector('accel','g'),frequency=frequency,
            smoothingSeconds=0,calibrationMode='Reconstructed preview; original mapping unavailable',
            grip='First recorded angle + example axes',cameraEnabled=False))
    timestamp=dt.datetime.strptime(path.name[8:28],'%Y-%m-%dT%H-%M-%SZ').replace(tzinfo=dt.timezone.utc)
    trace=dict(id=str(uuid.uuid4()),recordedAt=timestamp.timestamp()-978307200,
        origin='Imported Core Motion CSV · reconstructed preview',
        completion='Real recorded sensor input. Racket preview reconstructed from the first angle; original grip, smoothing, and game output were not recorded.',
        frames=frames,events=[],sourceFile=path.name,
        conditionUserReported=rows[0].get('condition_user_reported','Unknown'),
        exportNotes='Display-only sample, downsampled to at most 20 Hz. Capture date is the source session start; receipt latency is unknown.')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(trace,separators=(',',':'),allow_nan=False))
    print(json.dumps(dict(source=path.name,sourceEarbud=frames[0]['source'],frames=len(frames),
        duration=frames[-1]['capturedAt']-frames[0]['capturedAt'],output=str(args.output),mode=trace['origin'])))


if __name__=='__main__':main()
