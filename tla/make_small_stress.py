"""
Write a copy of ocip's tests/threads_stress.py with small sizes (2 domains,
2 threads, a few iterations), whose traces TLC can validate in seconds.

Usage: python3 make_small_stress.py <ocip>/tests/threads_stress.py <output>
"""

import sys

REPLACEMENTS = [
    ("DOMAINS = 4", "DOMAINS = 2"),
    ("THREADS = 8", "THREADS = 2"),
    ("    k = 2000", "    k = 3"),
    ("100_000", "5"),
    ("10_000", "5"),
    ("    k = 300", "    k = 3"),
    ("    k = 100\n", "    k = 3\n"),
    ("m.domains_incr(a, 2, 1000)", "m.domains_incr(a, 2, 5)"),
    ("2 * k + 2 * 1000", "2 * k + 2 * 5"),
    ("n = DOMAINS * 50", "n = DOMAINS * 3"),
    ("m.domains_loop(2, 100, callback)", "m.domains_loop(2, 3, callback)"),
    ("4 * 2 * 100", "4 * 2 * 3"),
    ("for _ in range(50):", "for _ in range(2):"),
    ("for j in range(200):", "for j in range(3):"),
    ("m.domains_loop(2, 50, callback)", "m.domains_loop(2, 3, callback)"),
    ("for x in range(100))", "for x in range(6))"),
    ("m.domains_loop(2, 10, lambda x: x)", "m.domains_loop(2, 3, lambda x: x)"),
    # The spin can end at once when the flag is set before.
    ("assert m.spin(flag) > 0", "assert m.spin(flag) >= 0"),
]


def main() -> None:
    source = open(sys.argv[1]).read()
    for old, new in REPLACEMENTS:
        if old not in source:
            sys.exit(f"not found: {old!r}")
        source = source.replace(old, new)
    open(sys.argv[2], "w").write(source)


main()
