"""Gate only ECS runtime; publish no output until the Git comparison is complete."""
import argparse
import os
import re
import selectors
import subprocess
import sys
import time

CHART = "charts/lgtm-stack/"
MAX_OUTPUT = 1048576
EXACT = {
    ".github/workflows/pull_request.yml",
    ".github/scripts/lgtm-stack/ecs-runtime-changes.py",
    ".github/scripts/lgtm-stack/test_ecs_runtime_changes.py",
    *(CHART + name for name in (
        "Chart.yaml", "Chart.lock", ".helmignore", "values.yaml", "values.schema.json",
        "templates/_gateway.tpl", "templates/_gateway-ecs.tpl", "templates/_gateway-transport.tpl",
        "templates/_helpers.tpl", "templates/applications.yaml", "templates/gateway.yaml",
        "presets/alloy-gateway.yaml", "presets/kube-prometheus-stack.yaml",
        "files/tests/test-ecs-receiver.sh", "files/tests/ecs-receiver-values.yaml",
        "files/tests/ecs-receiver-fixtures.py", "files/tests/ecs-receiver-runtime.py",
    )),
}


def relevant(path):
    return path in EXACT or path.startswith(CHART + "charts/") or (
        path.startswith(CHART + "tests/ecs") and path.endswith((".yaml", ".yml")))


def git(*args):
    with subprocess.Popen(["git", "--no-optional-locks", *args], shell=False,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as child:
        output, deadline = bytearray(), time.monotonic() + 15
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(child.stdout, selectors.EVENT_READ)
                while selector.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError("Git comparison timed out")
                    for key, _ in selector.select(remaining):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            selector.unregister(key.fileobj)
                        output.extend(chunk)
                        if len(output) > MAX_OUTPUT:
                            raise ValueError("Git output exceeds limit")
            if child.wait(timeout=max(0.01, deadline - time.monotonic())) != 0:
                raise ValueError("Git comparison failed")
            return bytes(output)
        except BaseException:
            child.kill()
            child.wait()
            raise


def classify(base, head):
    for sha in (base, head):
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("Expected a full commit SHA")
        git("cat-file", "-e", sha + "^{commit}")
    raw = git("diff", "--name-only", "--no-renames", "-z", base + "..." + head, "--")
    if raw and (not raw.endswith(b"\0") or b"\0\0" in raw):
        raise ValueError("Incomplete Git filename output")
    return any(relevant(name.decode("utf-8", "surrogateescape")) for name in raw.split(b"\0") if name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "head", "github-output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args(argv)
    try:
        run = classify(args.base, args.head)
        with open(args.github_output, "a", encoding="utf-8") as output:
            output.write("run=" + ("true" if run else "false") + "\n")
    except (OSError, ValueError, TimeoutError, subprocess.SubprocessError) as error:
        print(type(error).__name__ + ": ECS comparison/publication failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
