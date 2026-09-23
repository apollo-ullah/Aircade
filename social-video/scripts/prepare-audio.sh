#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
input_audio="$project_dir/public/room-audio.m4a"
output_audio="$project_dir/public/room-audio-mastered.wav"

# Light, deterministic dialogue cleanup. The original file stays untouched.
ffmpeg -hide_banner -loglevel warning -y \
  -i "$input_audio" \
  -af "highpass=f=80,lowpass=f=16000,afftdn=nr=8:nf=-35,dynaudnorm=f=150:g=7:p=.90:m=6,alimiter=limit=.891" \
  -c:a pcm_s24le \
  "$output_audio"
