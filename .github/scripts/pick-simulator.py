"""Print the UDID of an available iPhone simulator (newest iOS, iPhone 17 Pro first)."""

import json
import sys


def main() -> None:
    """Read `simctl list devices available -j` from stdin and print one UDID."""
    runtimes = json.load(sys.stdin)["devices"]
    ios = (name for name in runtimes if ".iOS-" in name)
    for runtime in sorted(ios, key=lambda r: tuple(map(int, r.split(".iOS-")[1].split("-"))), reverse=True):
        phones = [d for d in runtimes[runtime] if d["name"].startswith("iPhone")]
        if phones:
            chosen = next((d for d in phones if d["name"] == "iPhone 17 Pro"), phones[0])
            print(chosen["udid"])
            return
    sys.exit("No available iPhone simulator")


if __name__ == "__main__":
    main()
