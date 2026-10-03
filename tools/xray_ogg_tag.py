#!/usr/bin/env python3
"""Inject the X-Ray engine's binary ogg-comment block as the first vorbis
user comment, so xrSound parses it instead of logging
'! Invalid ogg-comment version'.

Layout (SoundRender_Source_loader.cpp, OGG_COMMENT_VERSION 0x0003):
    u32 version, float min_dist, float max_dist, float base_volume,
    u32 game_type, float max_ai_dist
"""
import struct, sys

def crc_table():
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04c11db7) & 0xffffffff if r & 0x80000000 else (r << 1) & 0xffffffff
        t.append(r)
    return t
CRC = crc_table()

def ogg_crc(buf):
    r = 0
    for b in buf:
        r = ((r << 8) & 0xffffffff) ^ CRC[((r >> 24) & 0xff) ^ b]
    return r

def parse_pages(data):
    pages, off = [], 0
    while off < len(data):
        assert data[off:off+4] == b'OggS', 'not an ogg page at %d' % off
        nsegs = data[off+26]
        seg = data[off+27:off+27+nsegs]
        body_off = off + 27 + nsegs
        body_len = sum(seg)
        pages.append({
            'htype': data[off+5],
            'granule': struct.unpack_from('<q', data, off+6)[0],
            'serial': struct.unpack_from('<I', data, off+14)[0],
            'seq': struct.unpack_from('<I', data, off+18)[0],
            'seg': list(seg),
            'body': data[body_off:body_off+body_len],
        })
        off = body_off + body_len
    return pages

def packets_of(page):
    """Split a page body into (bytes, complete) packets."""
    out, buf = [], b''
    pos = 0
    for lace in page['seg']:
        buf += page['body'][pos:pos+lace]
        pos += lace
        if lace < 255:
            out.append((buf, True))
            buf = b''
    if buf:
        out.append((buf, False))
    return out

def build_page(htype, granule, serial, seq, packets, verbatim=None):
    if verbatim is not None:
        seg, body = verbatim['seg'], verbatim['body']
    else:
        seg, body = [], b''
        for p in packets:
            n = len(p)
            seg.extend([255] * (n // 255))
            seg.append(n % 255)
            body += p
        assert len(seg) <= 255, 'header packets overflow one page'
    hdr = b'OggS' + bytes([0, htype]) + struct.pack('<qIII', granule, serial, seq, 0) \
          + bytes([len(seg)]) + bytes(seg)
    page = hdr + body
    return page[:22] + struct.pack('<I', ogg_crc(page)) + page[26:]

def rebuild_comment(packet, blob):
    """Replace user_comments[0] of a vorbis comment packet with `blob`."""
    assert packet[:7] == b'\x03vorbis', 'not a comment header'
    off = 7
    vlen, = struct.unpack_from('<I', packet, off); off += 4
    vendor = packet[off:off+vlen]; off += vlen
    n, = struct.unpack_from('<I', packet, off); off += 4
    comments = []
    for _ in range(n):
        clen, = struct.unpack_from('<I', packet, off); off += 4
        comments.append(packet[off:off+clen]); off += clen
    framing = packet[off]
    # A vorbis comment is 'key=value'; a blob without '=' is an X-Ray block
    # from an earlier run -- replace it so retagging stays idempotent.
    if comments and b'=' not in comments[0]:
        comments.pop(0)
    comments.insert(0, blob)
    out = b'\x03vorbis' + struct.pack('<I', len(vendor)) + vendor + struct.pack('<I', len(comments))
    for c in comments:
        out += struct.pack('<I', len(c)) + c
    return out + bytes([framing])

def tag(path, min_dist=1.0, max_dist=300.0, base_volume=1.0, game_type=0, max_ai=300.0):
    data = open(path, 'rb').read()
    pages = parse_pages(data)

    # Collect the three header packets and the pages they span.
    header_packets, used = [], 0
    pending = b''
    for i, pg in enumerate(pages):
        for buf, complete in packets_of(pg):
            pending += buf
            if complete:
                header_packets.append(pending)
                pending = b''
        used = i + 1
        if len(header_packets) >= 3:
            break
    assert len(header_packets) == 3 and not pending, 'unexpected header layout'

    blob = struct.pack('<IfffIf', 3, min_dist, max_dist, base_volume, game_type, max_ai)
    header_packets[1] = rebuild_comment(header_packets[1], blob)

    serial = pages[0]['serial']
    out = build_page(0x02, 0, serial, 0, [header_packets[0]])
    out += build_page(0x00, 0, serial, 1, header_packets[1:3])

    # Audio pages keep their lacing and granule positions; only the page
    # sequence can shift (the headers may have spanned more than two pages).
    seq = 2
    for pg in pages[used:]:
        out += build_page(pg['htype'], pg['granule'], serial, seq, None, pg)
        seq += 1

    open(path, 'wb').write(out)
    print('tagged', path)

def check(path):
    """Report the X-Ray block xrSound would parse; False if it would reject it."""
    pages = parse_pages(open(path, 'rb').read())
    packets, pending = [], b''
    for pg in pages[:2]:
        for buf, complete in packets_of(pg):
            pending += buf
            if complete:
                packets.append(pending)
                pending = b''
    if len(packets) < 2:
        print('BAD  %s: no comment header' % path)
        return False
    c = packets[1]
    off = 7
    vlen, = struct.unpack_from('<I', c, off); off += 4 + vlen
    n, = struct.unpack_from('<I', c, off); off += 4
    if n == 0:
        print('BAD  %s: no comments' % path)
        return False
    blen, = struct.unpack_from('<I', c, off); off += 4
    if blen < 24:
        print('BAD  %s: first comment is %d bytes, not an X-Ray block' % (path, blen))
        return False
    vers, mn, mx, vol, gt, ai = struct.unpack_from('<IfffIf', c, off)
    if vers != 3:
        print('BAD  %s: ogg-comment version %d' % (path, vers))
        return False
    print('ok   %s  min=%g max=%g vol=%g type=%d ai=%g' % (path, mn, mx, vol, gt, ai))
    return True

if __name__ == '__main__':
    args = sys.argv[1:]
    if args and args[0] == '--check':
        sys.exit(0 if all([check(p) for p in args[1:]]) else 1)
    for p in args:
        tag(p)
