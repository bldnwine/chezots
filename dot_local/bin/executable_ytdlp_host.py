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


def get_expected_filename(ytdlp, output_template, url):
    cmd = [ytdlp, '--print', 'filename', '-o', output_template, url]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return None
    lines = [l.strip() for l in result.stdout.split('\n') if l.strip()]
    return lines[-1] if lines else None


def main():
    try:
        params = get_message()
    except Exception as e:
        send_message({'type': 'error', 'message': f'Invalid message: {e}'})
        return

    url = params.get('url', '')
    quality = params.get('quality', 'best')
    fmt = params.get('format', 'mp4')
    save_path = params.get('savePath', '~/Videos/ytdlpx')
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

    try:
        subprocess.run(
            [ytdlp, '--simulate', url],
            capture_output=True, timeout=30, check=True
        )
    except subprocess.CalledProcessError:
        send_message({
            'type': 'error',
            'message': 'No downloadable video found at this URL'
        })
        return
    except subprocess.TimeoutExpired:
        pass

    output_template = os.path.join(save_path, '%(title)s [%(id)s].%(ext)s')
    filename = get_expected_filename(ytdlp, output_template, url)
    if filename is None:
        send_message({'type': 'error', 'message': 'Could not determine output filename'})
        return

    filepath = os.path.join(save_path, filename)
    if os.path.exists(filepath):
        base, ext = os.path.splitext(filename)
        n = 1
        while os.path.exists(os.path.join(save_path, f'{base} ({n}){ext}')):
            n += 1
        filename = f'{base} ({n}){ext}'
        filepath = os.path.join(save_path, filename)
        output_template = filepath

    send_message({'type': 'started'})

    cmd = [ytdlp, '-f', quality, '-o', output_template, url]
    if fmt:
        cmd.extend(['--merge-output-format', fmt])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=7200)
        if result.returncode == 0:
            send_message({
                'type': 'complete',
                'title': filename,
                'filepath': filepath
            })
            if notify_system and shutil.which('notify-send'):
                subprocess.Popen(['notify-send', 'ytdlpx', f'Complete: {filename}'])
        else:
            error_msg = result.stderr.strip() or 'Download failed'
            send_message({'type': 'error', 'message': error_msg})
    except subprocess.TimeoutExpired:
        send_message({'type': 'error', 'message': 'Download timed out (2h limit)'})
    except Exception as e:
        send_message({'type': 'error', 'message': str(e)})


if __name__ == '__main__':
    main()
