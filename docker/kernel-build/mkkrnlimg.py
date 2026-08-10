#!/usr/bin/env python3

import argparse
import os
import struct
import sys
import tempfile
from pathlib import Path


POLYNOMIAL = 0x04C10DB7
TAG = b"KRNL"
BUFFER_SIZE = 1024 * 1024


def make_crc_table():
    table = []
    for index in range(256):
        value = index << 24
        for _ in range(8):
            if value & 0x80000000:
                value = ((value << 1) ^ POLYNOMIAL) & 0xFFFFFFFF
            else:
                value = (value << 1) & 0xFFFFFFFF
        table.append(value)
    return table


CRC_TABLE = make_crc_table()


def update_crc(crc, data):
    for byte in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ CRC_TABLE[((crc >> 24) ^ byte) & 0xFF]
    return crc


def pack_image(payload_path, image_path):
    payload_size = payload_path.stat().st_size
    if payload_size > 0xFFFFFFFF:
        raise ValueError("payload is too large for the 32-bit Rockchip header")

    image_path.parent.mkdir(parents=True, exist_ok=True)
    temp_fd, temp_name = tempfile.mkstemp(prefix=f".{image_path.name}.", dir=image_path.parent)
    crc = 0

    try:
        with os.fdopen(temp_fd, "wb") as output_file, payload_path.open("rb") as input_file:
            output_file.write(TAG)
            output_file.write(struct.pack("<I", payload_size))
            while chunk := input_file.read(BUFFER_SIZE):
                output_file.write(chunk)
                crc = update_crc(crc, chunk)
            output_file.write(struct.pack("<I", crc))
        os.replace(temp_name, image_path)
        image_path.chmod(0o644)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise

    print(f"Packed {payload_path} -> {image_path}")
    print(f"Payload size: {payload_size} bytes")
    print(f"Rockchip CRC-32: 0x{crc:08x}")


def verify_image(image_path, payload_path=None):
    image_size = image_path.stat().st_size
    if image_size < 12:
        raise ValueError("image is shorter than the Rockchip header and CRC")

    with image_path.open("rb") as image_file:
        tag = image_file.read(4)
        if tag != TAG:
            raise ValueError(f"invalid tag: expected {TAG!r}, got {tag!r}")

        payload_size = struct.unpack("<I", image_file.read(4))[0]
        expected_image_size = payload_size + 12
        if image_size != expected_image_size:
            raise ValueError(
                f"invalid image size: header requires {expected_image_size}, got {image_size}"
            )

        crc = 0
        remaining = payload_size
        payload_file = payload_path.open("rb") if payload_path else None
        try:
            while remaining:
                chunk = image_file.read(min(BUFFER_SIZE, remaining))
                if not chunk:
                    raise ValueError("payload is truncated")
                crc = update_crc(crc, chunk)
                remaining -= len(chunk)
                if payload_file and chunk != payload_file.read(len(chunk)):
                    raise ValueError("payload differs from the source zImage")

            if payload_file and payload_file.read(1):
                raise ValueError("source zImage is larger than the packed payload")
        finally:
            if payload_file:
                payload_file.close()

        stored_crc = struct.unpack("<I", image_file.read(4))[0]
        if crc != stored_crc:
            raise ValueError(f"CRC mismatch: calculated 0x{crc:08x}, stored 0x{stored_crc:08x}")

    print(
        f"PASS: {image_path}: tag=KRNL payload={payload_size} "
        f"crc=0x{stored_crc:08x}"
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create or verify a Rockchip KRNL image used by the Pomera DM200"
    )
    parser.add_argument("--verify", action="store_true", help="verify an existing image")
    parser.add_argument("first", type=Path, help="input payload, or image with --verify")
    parser.add_argument("second", type=Path, nargs="?", help="output image, or expected payload")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        if args.verify:
            verify_image(args.first, args.second)
        else:
            if args.second is None:
                raise ValueError("output image path is required")
            pack_image(args.first, args.second)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
