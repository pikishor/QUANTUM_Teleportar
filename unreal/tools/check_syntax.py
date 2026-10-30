#!/usr/bin/env python3
"""Syntax/declaration check for the Unreal module WITHOUT Unreal installed.

Copies the module sources to a temp dir, expands the bits UnrealHeaderTool would generate (GENERATED_BODY -> Super typedef +
StaticClass, empty *.generated.h), points every engine #include at the declaration-only stub in ue-stubs/UEStub.h, then runs
`g++ -fsyntax-only` on each .cpp.

Catches: typos, missing members/declarations, wrong signatures, float/double template mismatches (FMath::Min etc).
Does NOT prove the code builds against the real engine. Usage: python3 unreal/tools/check_syntax.py
"""
import pathlib, re, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT.parent / "QuantumTeleportar" / "Source" / "QuantumTeleportar"
STUB = ROOT / "ue-stubs" / "UEStub.h"

CLASS_RE = re.compile(r"class\s+QUANTUMTELEPORTAR_API\s+(\w+)\s*:\s*public\s+(\w+)\s*\{\s*GENERATED_BODY\(\)", re.S)
INCLUDE_RE = re.compile(r'#include\s+"([^"]+)"')


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="qt-syntax-"))
    try:
        src, stubs = tmp / "src", tmp / "stubs"
        src.mkdir(); stubs.mkdir()
        shutil.copy(STUB, stubs / "UEStub.h")
        engine_headers = set()

        for f in SRC.iterdir():
            if f.suffix not in (".h", ".cpp"):
                continue
            text = f.read_text()
            text = CLASS_RE.sub(
                lambda m: f"class QUANTUMTELEPORTAR_API {m.group(1)} : public {m.group(2)}\n{{\npublic: typedef {m.group(2)} Super; static UClass* StaticClass();\nprivate:",
                text)
            (src / f.name).write_text(text)
            for inc in INCLUDE_RE.findall(text):
                if inc.endswith(".generated.h"):
                    (src / inc).write_text("#pragma once\n")
                elif not (SRC / inc).exists():
                    engine_headers.add(inc)

        for inc in engine_headers:
            p = stubs / inc
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('#pragma once\n#include "UEStub.h"\n')

        clang = shutil.which("clang++")
        compiler = [clang, "-ferror-limit=0"] if clang else ["g++", "-fmax-errors=0"]
        failed = 0
        for cpp in sorted(src.glob("*.cpp")):
            r = subprocess.run(
                compiler + ["-std=c++17", "-fsyntax-only", "-Wall", "-Wno-unused-parameter", "-Wno-reorder",
                            "-I", str(stubs), "-I", str(src), str(cpp)],
                capture_output=True, text=True)
            if r.returncode != 0:
                failed += 1
                print(f"--- {cpp.name}: FAILED")
                print(r.stderr.replace(str(src) + "/", "").replace(str(stubs) + "/", "stub:"))
            else:
                warn = r.stderr.strip()
                print(f"ok  {cpp.name}" + (f"  (warnings)\n{warn}" if warn else ""))
        print("\n%d file(s) failed" % failed if failed else "\nall files passed the stub-based syntax check")
        return 1 if failed else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
