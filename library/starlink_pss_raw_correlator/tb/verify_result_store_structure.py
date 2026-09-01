#!/usr/bin/env python3
"""Machine-check the resource/atomicity shape of the result publication store."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / "starlink_pss_result_store.v").read_text()


def require(pattern: str, message: str) -> None:
    if re.search(pattern, text, re.MULTILINE | re.DOTALL) is None:
        raise SystemExit(f"RESULT_STORE_STRUCTURE_FAIL {message}")


require(r"PACKET_WORDS\s*=\s*5'd26", "packet length is not fixed at 26 words")
require(r"PACKET_MAGIC\s*=\s*32'h3153_5350", "versioned packet magic missing")
require(
    r"ad_mem\s*#\s*\(.*?\.DATA_WIDTH\s*\(32\).*?\.ADDRESS_WIDTH\s*\(6\)",
    "result payload is not one 64x32 dual-clock memory",
)
require(
    r"starlink_pss_async_fifo\s*#\s*\(.*?\.DATA_WIDTH\s*\(1\).*?"
    r"\.ADDRESS_WIDTH\s*\(2\)",
    "publication descriptor is not the one-bit asynchronous FIFO",
)
require(
    r"descriptor_write_valid\s*=.*?writer_word_index\s*==\s*LAST_PACKET_WORD",
    "descriptor can be published before the final packet word",
)
require(
    r"result_memory_write\s*=\s*writer_active\s*&&\s*i_result_valid",
    "memory write is not coupled to the held producer packet",
)
require(
    r"effective_bank_free\s*=\s*engine_bank_free\s*\|\s*engine_release_event",
    "returned-bank CDC event is not included in allocation",
)
require(r"ASYNC_REG", "release-toggle synchronizer is not marked asynchronous")
if re.search(r"reg\s*\[611:0\]", text):
    raise SystemExit("RESULT_STORE_STRUCTURE_FAIL duplicate full-packet register found")

print(
    "RESULT_STORE_STRUCTURE_PASS packet_words=26 banks=2 payload_ram_bits=2048 "
    "descriptor_bits=1 full_packet_registers=0"
)
