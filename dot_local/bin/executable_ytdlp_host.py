#!/usr/bin/env python3
import sys
import json
import struct
import subprocess
import os
import shutil


def get_message():
    raw = sys.stdin.buffer.read(4)
    if not raw:
        sys.exit(0)
    length = struct.unpack('=I', raw)[0]
    return json.loads(sys.stdin.buffer.read(length).decode('utf-8'))


def send_message(msg):
    data = json.dumps(msg).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('=I', len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main():
    try:
        params = get_message()
    except Exception as e:
        send_message({'type': 'error', 'message': f'Invalid message: {e}'})
        return

    url = params.get('url', '')
    quality = params.get('quality', 'best')
    fmt = params.get('format', 'mp4')
    save_path = params.get('savePath', '~/Videos')
    audio_only = params.get('audioOnly', False)
    notify_system = params.get('notifySystem', False)

    if not url or not (url.startswith('http://') or url.startswith('https://')):
        send_message({'type': 'error', 'message': 'Invalid URL'})
        return

    save_path = os.path.expanduser(save_path)
    os.makedirs(save_path, exist_ok=True)

    ytdlp = shutil.which('yt-dlp')
    if not ytdlp:
        send_message({
            'type': 'error',
            'message': 'yt-dlp not found. Install with: sudo pacman -S yt-dlp'
        })
        return

    send_message({'type': 'started'})

    output_template = os.path.join(save_path, '%(title)s.%(ext)s')
    cmd = [ytdlp, '-o', output_template, '--embed-metadata', '--embed-thumbnail']
    if audio_only:
        cmd.extend(['--extract-audio', '--audio-format', fmt])
    else:
        cmd.extend(['-f', quality])
        if fmt:
            cmd.extend(['--merge-output-format', fmt])
    cmd.append(url)

    try:
        with open('/tmp/ytdlpx_debug.log', 'w') as dbg:
            result = subprocess.run(cmd, stdout=dbg, stderr=dbg, text=True, timeout=7200)
        if result.returncode == 0:
            send_message({
                'type': 'complete',
                'filepath': output_template
            })
            if notify_system and shutil.which('notify-send'):
                subprocess.Popen(['notify-send', 'ytdlpx', f'Download complete'])
        else:
            error_msg = result.stderr.strip() or 'Download failed'
            send_message({'type': 'error', 'message': error_msg})
    except subprocess.TimeoutExpired:
        send_message({'type': 'error', 'message': 'Download timed out (2h limit)'})
    except Exception as e:
        send_message({'type': 'error', 'message': str(e)})


if __name__ == '__main__':
    main()
