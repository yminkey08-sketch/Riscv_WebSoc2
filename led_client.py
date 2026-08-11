#!/usr/bin/env python3
"""TCP LED control client for RiscV WebSoC2.
Usage: python3 led_client.py [LED_VALUE]
  LED_VALUE: hex value 00-0F (e.g., 0F = all on, 01 = LED0 only, 00 = all off)
  Default: cycles through 0x0F, 0x00, 0x01, 0x02, 0x04, 0x08
"""
import socket, sys, time

HOST = "169.254.1.1"
PORT = 80

def set_led(value):
    """Send a single byte to control LED."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect((HOST, PORT))
        s.send(bytes([value & 0x0F]))
        s.close()
        print(f"LED set to 0x{value & 0x0F:02X}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        val = int(sys.argv[1], 16)
        set_led(val)
    else:
        # Cycle through LED patterns
        patterns = [0x0F, 0x00, 0x01, 0x02, 0x04, 0x08]
        for v in patterns:
            set_led(v)
            time.sleep(1)
