#!/usr/bin/env python3
"""Exercise the C loader from a consumer with no dependency-checkout artifacts."""
import os
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
include = root / "Sources/CLexiconONNXRuntime/include"
shim = root / "Sources/CLexiconONNXRuntime/LexiconONNXRuntime.c"

with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    mock = work / "mock.c"
    mock.write_text('''
#include "onnxruntime_c_api.h"
static const char *ORT_API_CALL version(void) { return "consumer-runtime"; }
static const OrtApiBase base = { .GetApi = NULL, .GetVersionString = version };
const OrtApiBase *ORT_API_CALL OrtGetApiBase(void) { return &base; }
''')
    probe = work / "probe.c"
    probe.write_text('''
#include "LexiconONNXRuntime.h"
#include <pthread.h>
#include <string.h>
static void *read_version(void *unused) {
    (void)unused;
    return strcmp(LexiconONNXRuntimeVersion(), "consumer-runtime") == 0 ? NULL : (void *)1;
}
int main(void) {
    pthread_t threads[16];
    for (int i = 0; i < 16; ++i) if (pthread_create(&threads[i], NULL, read_version, NULL)) return 2;
    for (int i = 0; i < 16; ++i) {
        void *result;
        if (pthread_join(threads[i], &result) || result != NULL) return 1;
    }
    return 0;
}
''')
    flags = ["cc", "-Wall", "-Wextra", "-Werror", "-I", str(include)]
    library = work / "libonnxruntime.so"
    subprocess.run(flags + ["-shared", "-fPIC", str(mock), "-o", str(library)], check=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("LEXICON_ONNX_RUNTIME_")}
    consumer = work / "consumer"
    consumer.mkdir()
    host = "linux-aarch64" if platform.machine() in ("aarch64", "arm64") else "linux-x64"
    cases = [
        ("consumer default", {}, [], consumer / f".build/onnx-runtime/current/lib/{host}"),
        ("library override", {"LEXICON_ONNX_RUNTIME_LIB": str(work / "custom")}, [], work / "custom"),
        ("root and platform overrides", {"LEXICON_ONNX_RUNTIME_ROOT": str(work / "root"),
            "LEXICON_ONNX_RUNTIME_PLATFORM": "custom-platform"}, [], work / "root/lib/custom-platform"),
    ]
    if host == "linux-x64":
        # Exercise selection only: this is still a host executable, not an ARM build.
        cases.append(("ARM64 default selection", {}, ["-D__aarch64__"],
            consumer / ".build/onnx-runtime/current/lib/linux-aarch64"))
    for index, (name, overrides, defines, directory) in enumerate(cases):
        directory.mkdir(parents=True, exist_ok=True)
        installed = directory / library.name
        installed.write_bytes(library.read_bytes())
        executable = work / f"probe-{index}"
        subprocess.run(flags + defines + [str(shim), str(probe), "-ldl", "-pthread", "-o", str(executable)], check=True)
        subprocess.run([str(executable)], cwd=consumer, env=env | overrides, check=True)
        installed.unlink()
        print(f"PASS: {name} (16 concurrent first loads)")
