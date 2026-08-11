import argparse
import json
import math
import statistics
import subprocess
import time


def run(command):
    started = time.perf_counter_ns()
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000_000
    if result.returncode != 0:
        raise SystemExit(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            + result.stderr.decode(errors="replace")
        )
    return elapsed


def measure(command, samples, warmups):
    for _ in range(warmups):
        run(command)
    values = [run(command) for _ in range(samples)]
    ordered = sorted(values)
    return {
        "command": command,
        "samplesSeconds": values,
        "p50Seconds": statistics.median(values),
        "p95Seconds": ordered[math.ceil(0.95 * len(ordered)) - 1],
    }


def output(command):
    return subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


parser = argparse.ArgumentParser()
parser.add_argument("--lunchpail", default=".build/release/lunchpail")
parser.add_argument("--lume", default="lume")
parser.add_argument("--samples", type=int, default=30)
parser.add_argument("--warmups", type=int, default=3)
arguments = parser.parse_args()

if arguments.samples < 1 or arguments.warmups < 0:
    raise SystemExit("samples must be positive and warmups cannot be negative")

lunchpail = measure(
    [arguments.lunchpail, "vm", "list", "--json"], arguments.samples, arguments.warmups
)
lume = measure([arguments.lume, "ls", "--format", "json"], arguments.samples, arguments.warmups)

result = {
    "recordedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "host": {
        "chip": output(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"]),
        "productVersion": output(["/usr/bin/sw_vers", "-productVersion"]),
        "buildVersion": output(["/usr/bin/sw_vers", "-buildVersion"]),
    },
    "samples": arguments.samples,
    "warmups": arguments.warmups,
    "lunchpail": lunchpail,
    "lume": lume,
    "p50Speedup": lume["p50Seconds"] / lunchpail["p50Seconds"],
}

print(json.dumps(result, indent=2, sort_keys=True))
