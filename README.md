# aurora-toolchain

Build pipeline for **the unified mingw toolchain bundle** that the
[Aurora IDE](https://github.com/nipscernlab/Aurora) ships
(`aurora-msys-vN.zip` → extracts to `components/Packages/msys/`).

This is a **project in its own right**: it packages the whole FOSS EDA stack
into one pinned, portable MSYS2/mingw64 snapshot — including the
**unprecedented part: running cocotb on Verilator under mingw** (the cocotb
wheel does not ship a Verilator VPI for Windows; we build it ourselves). This
repo exists so that work has history, a single source of truth for versions,
and a reproducible build — instead of living as scattered scripts inside Aurora.

---

## What the bundle contains

One mingw64 prefix (`msys/mingw64`) + a few MSYS shell utils (`msys/usr/bin`):

| Tool | Role in Aurora |
|------|----------------|
| **iverilog** + vvp | default Verilog simulator (Wave button) |
| **verilator** + verilator_bin | opt-in fast simulator; compiles a C++ model |
| **yosys** | synthesis → JSON hierarchy (PRISM) |
| **g++ / gcc / cc1plus** | **runs at RUNTIME** to compile the Verilator model |
| **perl, make, ccache** | verilator build driver + cache |
| **python 3.12 + cocotb 2.0.1** | cocotb testbenches — carries **both VPIs**: `libcocotbvpi_icarus.vpl` (from the wheel) **and** `libcocotbvpi_verilator.a` (built here) |

Not in the bundle (separate): `gtkwave-nipscern` (display + fst2vcd) and the
YANC compilers — each from their own repos. `netlistsvg` is an npm package.

## What's pinned, and why

See [`manifest.txt`](manifest.txt) for exact versions. The two hard pins:

- **gcc / gcc-libs = 15.1.0-5.** gcc **16.1.0-5** shipped a broken libstdc++
  (`std::string` move ctor undefined) — the cocotb VPI fails to link against it.
  Since **g++ runs at runtime** (Verilator emits C++ that must be compiled), the
  bundle must carry a working g++. Stay on 15 until a fixed 16+/17 is verified.
- **python = 3.12.11-1.** cocotb links `-lpython3.X`; the bundle Python minor
  must match what cocotb was built against. 3.14 breaks the cocotb build.

Everything else (iverilog 13, yosys 0.56, verilator 5.048, ccache, perl, make)
tracks the latest MSYS2 — recorded in the manifest for reproducibility.

> **Reproducibility caveat:** MSYS2 is rolling-release. To rebuild byte-for-byte
> later, pin the exact package versions in `manifest.txt` **and** archive the
> `.pkg.tar.zst` files (CI uploads them as a build artifact). Without that, a
> rebuild pulls whatever MSYS2 ships that day.

## The cocotb-on-Verilator recipe (the hard part)

The cocotb wheel gates the Verilator VPI behind `if os.name == "posix"`, so
Windows gets no `libcocotbvpi_verilator`. We build it by hand:

1. **Static** `libcocotbvpi_verilator.a` (g++/ar) from `cocotb/share/lib/vpi/*.cpp`
   with `-DVERILATOR -DPLI_DLLISPEC=` + the Verilator includes. `-DPLI_DLLISPEC=`
   is the key: makes the `vpi_*` symbols plain (no `__declspec(dllimport)`), so
   they match the `verilated_vpi.o` linked into the exe. Static because Verilator
   links the VPI into the model exe (no dlopen).
2. **Patch `cocotb_tools/runner.py`** (Verilator class): each flag as its own
   `-LDFLAGS <token>` (the verilator perl wrapper splits multi-word on spaces);
   **no** `-Wl,-rpath` (verilator escapes the commas); link
   `-lcocotbvpi_verilator -lgpi -lgpilog -lcocotbutils -static-libstdc++ -static-libgcc`;
   `shutil.which` fallback (verilator is an extensionless perl script).
3. cocotb's Python is the **bundle's mingw python** — and the same one runs
   cocotb-**icarus** (its `.vpl` ships in the wheel), so Aurora uses **one** Python
   for both backends.

## Build pipeline

Run in an **MSYS2 MINGW64** shell, in order. (`<out>` = e.g. `dist/msys`.)

```bash
bash build/10-install-packages.sh                 # pacman the pinned toolchain (+ pins)
bash build/20-build-cocotb-vpi.sh                 # venv + cocotb + build the static VPI
bash build/40-assemble-bundle.sh dist/msys        # copy the mingw prefix + bake cocotb
bash build/45-trim-bundle.sh    dist/msys         # slim ~40% (validated by smoke)
bash build/50-smoke.sh          dist/msys         # 4-flow gate — MUST be 4/4 PASS
bash build/60-package.sh        dist/msys dist/aurora-msys-v1.zip
```

`30-package-cocotb.sh` / `21-rebuild-vpi.sh` are the original helpers (operate on
an existing bundle); `40-assemble` formalizes the from-scratch path. **Always
gate on `50-smoke.sh` (4/4) before publishing.**

## Cutting / evolving a release

1. Edit [`manifest.txt`](manifest.txt) (bump a version, e.g. gcc when a fixed
   16+/17 is verified, or python, or any tool) and `bundle_tag`.
2. Run the pipeline (or let CI do it — see `.github/workflows/build.yml`).
3. Confirm `50-smoke.sh` is 4/4.
4. `gh release create <bundle_tag> dist/aurora-msys-<v>.zip --prerelease`.
5. In **Aurora**, bump `MSYS_TAG` / `MSYS_FILENAME` in
   `components/Scripts/download-toolchain.js` to the new tag (and, if this repo
   hosts the release, point `GITHUB_REPO` at `aurora-toolchain`).

That's the whole evolution path: **one manifest bump → rebuild → smoke → publish**.

## How Aurora consumes it

`download-toolchain.js` fetches `aurora-msys-vN.zip` from the pinned release and
extracts it to `components/Packages/msys/`. The sentinels it checks:
`msys/mingw64/bin/verilator_bin.exe` (bundle present) and
`.../site-packages/cocotb/libs/libcocotbvpi_verilator.a` (cocotb present).
