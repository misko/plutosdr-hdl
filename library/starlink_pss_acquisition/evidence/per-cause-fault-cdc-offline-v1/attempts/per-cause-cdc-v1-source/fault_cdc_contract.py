"""Literal inverse of ONLY the new per-cause CDC option."""

BASE = "2ccfac2e70da2689d97eee75cbfc78e2589813a2"


def restore_fault_cdc(source):
    parameter = "  parameter integer PER_CAUSE_FAULT_CDC = 0,\n"
    checks = """    if (PER_CAUSE_FAULT_CDC !== 0 && PER_CAUSE_FAULT_CDC !== 1)
      $fatal(1, "PER_CAUSE_FAULT_CDC must be zero or one");
    if (PER_CAUSE_FAULT_CDC && !DISTRIBUTED_FAST_FAULT)
      $fatal(1, "PER_CAUSE_FAULT_CDC requires DISTRIBUTED_FAST_FAULT");
"""
    for addition in (parameter, checks):
        if source.count(addition) != 1:
            raise ValueError("nonunique CDC inverse addition")
        source = source.replace(addition, "", 1)
    begin = "  // BEGIN PER_CAUSE_FAULT_CDC:"
    end = "  // END PER_CAUSE_FAULT_CDC\n"
    if source.count(begin) != 1 or source.count(end) != 1:
        raise ValueError("nonunique CDC body")
    start, stop = source.index(begin), source.index(end) + len(end)
    legacy = """  always @(posedge clk)
    if (!slow_running) fast_fault_slow <= 0;
    else fast_fault_slow <= {fast_fault_slow[0], fast_fault};
"""
    if source[start:stop].count(legacy) != 1:
        raise ValueError("legacy two-stage body changed")
    return source[:start] + legacy + source[stop:]
