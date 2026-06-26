import struct
import sys

MACHO_PATH = r'E:\muad\muadclaude\app\extracted\ipa_payload\Payload\Runner.app\Runner'
DYLIB_PATH = '@executable_path/Frameworks/unlock_academia.dylib'

def main():
    with open(MACHO_PATH, 'rb') as f:
        data = bytearray(f.read())

    magic = struct.unpack('<I', data[0:4])[0]
    if magic != 0xFEEDFACF:
        print(f'Not a 64-bit Mach-O: magic={magic:#x}')
        return False

    # Parse header
    hdr = struct.unpack('<IIIIIIII', data[0:32])
    ncmds = hdr[4]
    sizeofcmds = hdr[5]

    # Find the end of load commands
    cmd_end = 32 + sizeofcmds
    print(f'ncmds={ncmds}, sizeofcmds={sizeofcmds}, end_at={cmd_end}')

    # Find first segment fileoff to see slack space
    pos = 32
    min_fileoff = float('inf')
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', data[pos:pos+8])
        if cmd == 0x19:  # LC_SEGMENT_64
            seg = struct.unpack('<16sQQQQIIII', data[pos+8:pos+72])
            fileoff = seg[3]
            if fileoff > 0 and fileoff < min_fileoff:
                min_fileoff = fileoff
        pos += cmdsize

    slack = int(min_fileoff) - cmd_end
    print(f'First segment fileoff={int(min_fileoff)}, slack={slack} bytes')

    # Build LC_LOAD_DYLIB command
    name_bytes = DYLIB_PATH.encode('utf-8') + b'\x00'
    # Align to 8 bytes
    name_pad = (8 - (len(name_bytes) % 8)) % 8
    name_bytes += b'\x00' * name_pad
    dylib_cmd_size = 24 + len(name_bytes)  # 12 (cmd+cmdsize) + 12 (dylib struct) + name

    # dylib struct: offset(4) timestamp(4) current_version(4) compatibility_version(4)
    dylib_cmd = struct.pack('<II', 0x0C, dylib_cmd_size)  # LC_LOAD_DYLIB
    dylib_cmd += struct.pack('<IIII', 24, 0, 0, 0)  # offset from start of dylib_command
    dylib_cmd += name_bytes

    print(f'LC_LOAD_DYLIB size={dylib_cmd_size}')
    print(f'  path={DYLIB_PATH}')

    if slack >= dylib_cmd_size:
        # Insert without shifting
        data[cmd_end:cmd_end] = dylib_cmd
        print(f'Inserted in slack space at offset {cmd_end}')
    else:
        # Need to shift everything after load commands
        # But also need to update __TEXT segment fileoff and all segment offsets
        # This is more complex. For now, let's find if there's room in the __TEXT segment
        # which usually has padding at the end before the next segment
        print(f'Not enough slack ({slack} < {dylib_cmd_size}), needs shifting')
        
        # Check if there's enough room in the __TEXT segment (before __stubs etc)
        # Many apps have padding between segments
        # Let's find the gap between last load command and first segment
        # Actually, let's just try shifting - we'll update __TEXT's fileoff by the increase
        
        # Find __TEXT segment
        pos = 32
        text_seg = None
        last_cmd_end = 0
        for i in range(ncmds):
            cmd, cmdsize = struct.unpack('<II', data[pos:pos+8])
            if cmd == 0x19:
                seg = struct.unpack('<16sQQQQIIII', data[pos+8:pos+72])
                segname = seg[0].rstrip(b'\x00').decode()
                if segname == '__TEXT':
                    text_seg = seg
                    text_seg_pos = pos
                if seg[3] > 0 and seg[3] < min_fileoff:
                    min_fileoff = seg[3]
            last_cmd_end = pos + cmdsize
            pos += cmdsize

        if not text_seg:
            print('ERROR: Could not find __TEXT segment')
            return False

        # Check how much padding there is before the first segment data
        gap_start = cmd_end  # 32 + sizeofcmds
        gap_end = int(min_fileoff)
        actual_gap = gap_end - gap_start
        print(f'Gap between load cmds and first data: {actual_gap} bytes')

        if actual_gap >= dylib_cmd_size:
            # Just use the gap
            pass
        else:
            # Need to shift __TEXT segment and all subsequent segments
            shift = dylib_cmd_size - actual_gap
            print(f'Shifting all segments by {shift} bytes')
            
            # Extend the file by shift bytes
            data.extend(b'\x00' * shift)
            
            # Update all LC_SEGMENT_64 file offsets
            pos = 32
            for i in range(ncmds):
                cmd, cmdsize = struct.unpack('<II', data[pos:pos+8])
                if cmd == 0x19:
                    seg_off = pos + 8
                    seg = struct.unpack('<16sQQQQIIII', data[seg_off:seg_off+64])
                    fileoff = seg[3]
                    if fileoff > 0:
                        new_fileoff = fileoff + shift
                        data[seg_off+8:seg_off+16] = struct.pack('<Q', new_fileoff)
                        print(f'  Updated segment fileoff: {fileoff} -> {new_fileoff}')
                pos += cmdsize
            
            # Move the data from gap_start onwards by shift bytes
            # Actually, we inserted the dylib_cmd into the gap...
            # No, we need to insert at cmd_end and move everything after cmd_end forward
            insert_at = cmd_end
            # Shift data from cmd_end to end-of-file by dylib_cmd_size
            src = data[insert_at : -(dylib_cmd_size - actual_gap)] if actual_gap > 0 else data[insert_at:]
            # Hmm, this is getting complex. Let me rethink.
        
        print('Complex shift needed - using alternative approach')
        # Instead: we insert the dylib cmd after the __TEXT segment content
        # Actually no, let me use a different approach entirely
        return False

    # Update header
    new_ncmds = ncmds + 1
    new_sizeofcmds = sizeofcmds + dylib_cmd_size
    data[4:8] = struct.pack('<I', new_ncmds)
    data[8:12] = struct.pack('<I', new_sizeofcmds)

    # Write back
    with open(MACHO_PATH, 'wb') as f:
        f.write(data)

    print(f'Done. ncmds={new_ncmds}, sizeofcmds={new_sizeofcmds}')
    return True

if __name__ == '__main__':
    if not main():
        sys.exit(1)
