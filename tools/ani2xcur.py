#!/usr/bin/env python3
"""Convert a Windows cursor pack (.ani/.cur) into an X11 Xcursor theme.

usage: ani2xcur.py <src-dir> <theme-dir> [Role=filename ...]

Roles come from the pack's install.inf when it has one (authoritative), and
from filename keywords otherwise.  Role= arguments override either.
"""
import struct, io, os, sys, glob, re
from PIL import Image, ImageChops

JIFFY_MS = 1000.0 / 60.0
SIZES = [24, 32, 48, 64, 96, 128]

# ---------------------------------------------------------------- ANI / CUR

def riff_chunks(buf, off, end):
    while off + 8 <= end:
        cid = buf[off:off+4]
        sz = struct.unpack_from('<I', buf, off+4)[0]
        yield cid, off + 8, sz
        off += 8 + sz + (sz & 1)

def decode_icon(data):
    """Largest entry of an ICO/CUR blob -> (RGBA image, xhot, yhot)."""
    itype, count = struct.unpack_from('<HH', data, 2)
    best = None
    for i in range(count):
        w, h, _nc, _r, p1, p2, _br, _off = struct.unpack_from('<BBBBHHII', data, 6 + 16*i)
        w, h = w or 256, h or 256
        if best is None or w * h > best[0] * best[1]:
            best = (w, h, p1, p2)
    _w, _h, p1, p2 = best
    im = Image.open(io.BytesIO(data)).convert('RGBA')
    xhot, yhot = (p1, p2) if itype == 2 else (0, 0)   # CUR keeps the hotspot here
    return im, min(xhot, im.width - 1), min(yhot, im.height - 1)

def read_cursor(path):
    """-> [(image, xhot, yhot, delay_ms)]; one entry for a static cursor."""
    buf = open(path, 'rb').read()
    if buf[:4] != b'RIFF':                      # plain .cur
        im, xh, yh = decode_icon(buf)
        return [(im, xh, yh, 0)]
    end = 8 + struct.unpack_from('<I', buf, 4)[0]
    frames, rates, seq, disp = [], None, None, 1
    for cid, o, sz in riff_chunks(buf, 12, end):
        if cid == b'anih':
            disp = struct.unpack_from('<9I', buf, o)[7] or 1
        elif cid == b'rate':
            rates = struct.unpack_from('<%dI' % (sz // 4), buf, o)
        elif cid == b'seq ':
            seq = struct.unpack_from('<%dI' % (sz // 4), buf, o)
        elif cid == b'LIST' and buf[o:o+4] == b'fram':
            for c2, o2, s2 in riff_chunks(buf, o + 4, o + sz):
                if c2 == b'icon':
                    frames.append(decode_icon(buf[o2:o2+s2]))
    order = list(seq) if seq else list(range(len(frames)))
    out = []
    for step, idx in enumerate(order):
        jiff = rates[step] if rates and step < len(rates) else disp
        im, xh, yh = frames[idx % len(frames)]
        out.append((im, xh, yh, max(10, int(round(jiff * JIFFY_MS)))))
    return out

# ------------------------------------------------------------------ Xcursor

def _premultiply(im):
    """Xcursor stores premultiplied ARGB; straight alpha turns the (white)
    RGB of fully transparent pixels into an opaque box around the cursor."""
    r, g, b, a = im.split()
    return Image.merge('RGBA', (ImageChops.multiply(r, a),
                                ImageChops.multiply(g, a),
                                ImageChops.multiply(b, a), a))

def _clamp(im):
    """LANCZOS overshoots, so a channel can exceed alpha; clamp it back."""
    r, g, b, a = im.split()
    return Image.merge('RGBA', (ImageChops.darker(r, a),
                                ImageChops.darker(g, a),
                                ImageChops.darker(b, a), a))

def write_xcursor(path, frames, sizes):
    images = []
    for size in sizes:
        for im, xh, yh, delay in frames:
            pm = _premultiply(im)
            if im.width != size:
                k = size / im.width
                pm = _clamp(pm.resize((size, int(round(im.height * k))), Image.LANCZOS))
                xh2, yh2 = int(round(xh * k)), int(round(yh * k))
            else:
                xh2, yh2 = xh, yh
            images.append((size, pm, min(xh2, pm.width - 1), min(yh2, pm.height - 1), delay))
    pos = 16 + 12 * len(images)
    toc, body = b'', b''
    for size, im, xh, yh, delay in images:
        toc += struct.pack('<III', 0xfffd0002, size, pos + len(body))
        body += struct.pack('<9I', 36, 0xfffd0002, size, 1,
                            im.width, im.height, xh, yh, delay)
        body += im.tobytes('raw', 'BGRA')            # little-endian ARGB
    with open(path, 'wb') as fh:
        fh.write(b'Xcur' + struct.pack('<III', 16, 0x00010000, len(images)) + toc + body)

# -------------------------------------------------------------- role tables
# Windows registry cursor name -> (canonical X11 name, aliases).
# Every alias must be claimed by exactly one role; main() enforces that.
ROLES = {
 'Arrow':       ('default', ['left_ptr', 'arrow', 'top_left_arrow',
                             'context-menu', 'dnd-none', 'default_arrow']),
 'Hand':        ('pointing_hand', [
                    'pointer', 'hand', 'hand1', 'hand2', 'pointing-hand',
                    'grab', 'openhand', 'alias', 'dnd-link', 'link',
                    'copy', 'dnd-copy',
                    'e29285e634086352946a0e7090d73106',
                    '9d800788f1b08800ae810202380a0822',
                    '640fb0e74195791501fd1ed57b41487f',
                    '1081e37283d90000800003c07f3ef6bf',
                    '6407b0e94181790501fd1e167b474872',
                    'b66166c04f8c3109214a4fbd64a50fc8']),
 'IBeam':       ('xterm', ['ibeam', 'text']),
 'Crosshair':   ('crosshair', ['cross', 'tcross', 'cross_reverse',
                               'diamond_cross', 'cell', 'color-picker']),
 'Help':        ('help', ['question_arrow', 'whats_this', 'left_ptr_help',
                          'dnd-ask', '5c6cd98b3f3ebcb1f9c7f1c204630408',
                          'd9ce0ab605698f320427677b458ad60b']),
 'Wait':        ('wait', ['watch', 'clock', '0426c94ea35c87780ff01dc239897213']),
 'AppStarting': ('progress', ['left_ptr_watch', 'half-busy',
                              '00000000000000020006000e7e9ffc3f',
                              '08e8e1c95fe2fc01f976f1e063a24ccd',
                              '3ecb610c1bf2410f44200f48c40d3599',
                              '9116a3ea924ed2162ecab71ba103b17f']),
 'No':          ('not-allowed', ['forbidden', 'no-drop', 'dnd-no-drop',
                                 'crossed_circle', 'circle',
                                 '03b6e0fcb3499374a867c041f52298f0',
                                 '03b6e0fcb3499374a867d041f52298f0']),
 'SizeAll':     ('fleur', ['move', 'size_all', 'all-scroll', 'grabbing',
                           'closedhand', 'dnd-move',
                           '4498f0e0c1937ffe01fd06f973665830',
                           '9081237383d90e509aa00f00170e968f']),
 'SizeNS':      ('sb_v_double_arrow', [
                    'ns-resize', 'v_double_arrow', 'size_ver', 'double_arrow',
                    'row-resize', 'n-resize', 's-resize', 'top_side',
                    'bottom_side', 'based_arrow_up', 'based_arrow_down',
                    'sb_up_arrow', 'sb_down_arrow',
                    '00008160000006810000408080010102',
                    '2870a09082c103050810ffdffffe0204']),
 'SizeWE':      ('sb_h_double_arrow', [
                    'ew-resize', 'h_double_arrow', 'size_hor', 'col-resize',
                    'e-resize', 'w-resize', 'left_side', 'right_side',
                    'sb_left_arrow', 'sb_right_arrow',
                    '028006030e0e7ebffc7f7070c0600140',
                    '14fef782d02440884392942c11205230']),
 'SizeNWSE':    ('size_fdiag', ['nwse-resize', 'bd_double_arrow', 'nw-resize',
                                'se-resize', 'top_left_corner',
                                'bottom_right_corner',
                                'c7088f0f3e6c8088236ef8e1e3e70000',
                                '38c5dff7c7b8962045400281044508d2']),
 'SizeNESW':    ('size_bdiag', ['nesw-resize', 'fd_double_arrow', 'ne-resize',
                                'sw-resize', 'top_right_corner',
                                'bottom_left_corner',
                                'fcf1c3c7cd4491d801f1e1c78f100000',
                                '50585d75b494802d0151028115016902']),
 'UpArrow':     ('up_arrow', ['center_ptr', 'up-arrow']),
 'NWPen':       ('pencil', ['draft', 'draft_large', 'draft_small']),
}
# Filename keywords, for packs that ship no install.inf.
KEYWORDS = {
 'Arrow':       ['normal select', 'normal', 'arrow', 'pointer'],
 'Hand':        ['link select', 'link'],
 'IBeam':       ['text select', 'text', 'beam'],
 'Crosshair':   ['precision select', 'precision', 'crosshair'],
 'Help':        ['help select', 'help'],
 'Wait':        ['busy', 'wait'],
 'AppStarting': ['working in background', 'working', 'appstarting'],
 'No':          ['unavailable', 'no'],
 'SizeAll':     ['move'],
 'SizeNS':      ['vertical resize', 'vertical'],
 'SizeWE':      ['horizontal resize', 'horizontal'],
 'SizeNWSE':    ['diagonal resize 1', 'diagonal1'],
 'SizeNESW':    ['diagonal resize 2', 'diagonal2'],
 'UpArrow':     ['alternate select', 'alternate', 'uparrow'],
 'NWPen':       ['handwriting', 'pen'],
}
# Names with no art in a pack fall back to another cursor.
FALLBACKS = {
 'default': ['up_arrow', 'center_ptr', 'right_ptr', 'draft_large', 'draft_small',
             'pencil', 'dotbox', 'X_cursor', 'x-cursor', 'zoom-in', 'zoom-out',
             'vertical-text', 'plus'],
}

# ------------------------------------------------------------------ mapping

def roles_from_inf(path):
    """Parse install.inf: [Wreg] maps a Windows cursor name to a %var%,
    [Strings] resolves that var to a filename."""
    txt = open(path, 'rb').read().decode('cp1251', 'replace')
    strings, wreg, section = {}, {}, None
    for line in txt.splitlines():
        line = line.strip()
        if line.startswith('['):
            section = line.strip('[]').lower(); continue
        if section == 'strings' and '=' in line:
            k, v = line.split('=', 1)
            strings[k.strip()] = v.strip().strip('"')
        elif section == 'wreg' and 'Control Panel\\Cursors' in line:
            parts = [p.strip() for p in line.split(',')]
            if len(parts) < 5 or not parts[2]:
                continue
            m = re.search(r'%([A-Za-z0-9_]+)%"?\s*$', parts[-1])
            if m:
                wreg[parts[2]] = m.group(1)
    return {reg: strings[var] for reg, var in wreg.items() if var in strings}

def roles_from_names(src):
    files = [os.path.basename(p) for p in
             glob.glob(os.path.join(src, '*.ani')) + glob.glob(os.path.join(src, '*.cur'))]
    out = {}
    for role, keys in KEYWORDS.items():
        best = None
        for f in files:
            stem = os.path.splitext(f)[0].lower().replace('_', ' ')
            for rank, k in enumerate(keys):
                if k in stem:
                    # prefer an earlier keyword, then the shortest name (v1 over v2)
                    score = (rank, len(stem))
                    if best is None or score < best[0]:
                        best = (score, f)
        if best:
            out[role] = best[1]
    return out

# --------------------------------------------------------------------- main

def main(src, out, sizes, overrides):
    inf = glob.glob(os.path.join(src, '*.inf'))
    if inf:
        mapping = roles_from_inf(inf[0])
        print('roles from %s' % os.path.basename(inf[0]))
    else:
        mapping = roles_from_names(src)
        print('roles guessed from filenames (no install.inf)')
    # registry names vary in case between packs (crosshair vs Crosshair)
    mapping = {k.lower(): v for k, v in mapping.items()}
    mapping.update({k.lower(): v for k, v in overrides.items()})
    unmapped = sorted(k for k in mapping if k not in {r.lower() for r in ROLES})

    cur_dir = os.path.join(out, 'cursors')
    os.makedirs(cur_dir, exist_ok=True)

    made = {}
    for role, (canonical, aliases) in ROLES.items():
        fn = mapping.get(role.lower())
        if not fn:
            print('  - %-12s no art in pack' % role); continue
        path = os.path.join(src, fn)
        if not os.path.exists(path):
            print('  ! %-12s missing file %s' % (role, fn)); continue
        frames = read_cursor(path)
        write_xcursor(os.path.join(cur_dir, canonical), frames, sizes)
        made[canonical] = aliases
        print('  %-12s %-26s -> %-18s %2d frame(s)' % (role, fn, canonical, len(frames)))

    claimed = {}
    for canonical, aliases in made.items():
        for a in aliases:
            if a in claimed:
                raise SystemExit('alias %r claimed by both %r and %r'
                                 % (a, claimed[a], canonical))
            if a in made:
                raise SystemExit('alias %r collides with a real cursor' % a)
            claimed[a] = canonical
    for canonical, aliases in made.items():
        for a in aliases + FALLBACKS.get(canonical, []):
            link = os.path.join(cur_dir, a)
            if os.path.exists(link) or os.path.islink(link):
                continue
            os.symlink(canonical, link)
    for a in claimed:
        assert os.path.islink(os.path.join(cur_dir, a)), 'alias not created: ' + a

    theme = os.path.basename(out.rstrip('/'))
    for name, body in (('index.theme', 'Comment=Converted from a Windows cursor pack\nInherits=Adwaita\n'),
                       ('cursor.theme', 'Inherits=%s\n' % theme)):
        with open(os.path.join(out, name), 'w') as fh:
            fh.write('[Icon Theme]\nName=%s\n%s' % (theme, body))
    if unmapped:
        print('\nno X11 equivalent, skipped: %s' % ', '.join(unmapped))
    print('installed "%s" (%d cursors, %d names) -> %s'
          % (theme, len(made), len(made) + len(os.listdir(cur_dir)) - len(made), out))

if __name__ == '__main__':
    src, out = sys.argv[1], sys.argv[2]
    main(src, out, SIZES, dict(a.split('=', 1) for a in sys.argv[3:]))
