#!/usr/bin/env python3
"""Upload firmware to RiscV_WebSoC via UART LCPU protocol.

Protocol: ASCII text over 115200 bps UART
  Format: s<w|r><8-hex-addr><8-hex-data>\r
  Example: sw000100000C00006F\r
  Start marker: 's', Op: 'w'=write/'r'=read, End: '\r'
  Total: 19 bytes per command
"""

import sys
import time
import struct
import serial
import argparse

START_MARKER = ord('s')
WRITE_OP = ord('w')
READ_OP = ord('r')
END_MARKER = ord('\r')

# From project build settings
DEFAULT_BASE_ADDR = 0x10000   # word address base for instruction RAM
DEFAULT_RESET_ADDR = 0x100    # byte offset in binary where code starts
RESET_REG = 0x100             # reset control register address
LED_REG = 0x10                # LED register address


def read_firmware(path):
    """Read firmware binary file."""
    with open(path, 'rb') as f:
        return f.read()


def bin_to_words(data, reset_offset=0x100):
    """Convert binary to list of (word_addr, word_data) tuples.

    Strips the first `reset_offset` bytes (which contain the
    reset vector preamble), then groups remaining bytes into
    32-bit little-endian words.
    """
    # Skip reset offset bytes
    code = data[reset_offset:]

    words = []
    for i in range(0, len(code) - (len(code) % 4), 4):
        word_bytes = code[i:i+4]
        word_val = struct.unpack('<I', word_bytes)[0]
        words.append(word_val)

    return words


def build_uart_cmd(write=True, addr=0, data=0):
    """Build a UART LCPU command.
    Returns bytes: s<w|r><8-hex-addr><8-hex-data>\r
    """
    op = 'w' if write else 'r'
    cmd = f"s{op}{addr:08X}{data:08X}\r"
    return cmd.encode('ascii')


def upload_firmware(ser, words, base_addr=0x10000, verbose=True):
    """Upload firmware words via UART.

    Protocol sequence:
    1. Write reset vector = 0  (hold CPU in reset)
    2. Write each 32-bit word to instruction RAM
    3. Write reset vector = 1  (release CPU reset)
    4. Write LED = 0x5         (optional: signal success)
    """
    cmds = []

    # Step 1: Hold CPU in reset
    cmds.append(build_uart_cmd(write=True, addr=0x100, data=0x0))

    # Step 2: Write firmware words
    for i, word in enumerate(words):
        addr = base_addr + i
        cmds.append(build_uart_cmd(write=True, addr=addr, data=word))

    # Step 3: Release CPU reset
    cmds.append(build_uart_cmd(write=True, addr=0x100, data=0x1))

    # Step 4: Signal success (set LED)
    cmds.append(build_uart_cmd(write=True, addr=0x10, data=0x5))

    total = len(cmds)
    for idx, cmd in enumerate(cmds):
        ser.write(cmd)
        ser.flush()

        if verbose and idx % 10 == 0:
            pct = (idx + 1) * 100 // total
            bar = '#' * (pct // 5) + '-' * (20 - pct // 5)
            print(f"\r[{bar}] {idx+1}/{total} ({pct}%)", end='', flush=True)

        # Small delay between commands (LCPU state machine needs time)
        time.sleep(0.002)

    if verbose:
        print(f"\r[####################] {total}/{total} (100%)")
        print(f"Upload complete: {len(words)} words, {len(words)*4} bytes")


def main():
    parser = argparse.ArgumentParser(description='Upload firmware to RiscV_WebSoC via UART')
    parser.add_argument('firmware', help='Firmware binary file (out/firmware.bin)')
    parser.add_argument('-p', '--port', default='/dev/ttyACM0', help='UART port')
    parser.add_argument('-b', '--baud', type=int, default=115200, help='Baud rate')
    parser.add_argument('--base', type=lambda x: int(x, 0), default=DEFAULT_BASE_ADDR,
                        help='Base word address (default: 0x10000)')
    parser.add_argument('--offset', type=lambda x: int(x, 0), default=DEFAULT_RESET_ADDR,
                        help='Byte offset in binary (default: 0x100)')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode')
    args = parser.parse_args()

    # Read firmware
    data = read_firmware(args.firmware)
    print(f"Firmware: {len(data)} bytes from {args.firmware}")

    # Convert to words
    words = bin_to_words(data, args.offset)
    print(f"Words: {len(words)} (base addr: 0x{args.base:X})")

    # Open UART
    ser = serial.Serial(args.port, args.baud, timeout=1)
    print(f"UART: {args.port} @ {args.baud} bps")

    # Upload
    upload_firmware(ser, words, args.base, verbose=not args.quiet)

    ser.close()
    print("Done!")


if __name__ == '__main__':
    main()
