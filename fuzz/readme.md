# About fuzzing

Fuzzing is done by [OSS-Fuzz](https://google.github.io/oss-fuzz/).
It works by creating a project-specific binary that combines fuzzer
itself and a project provided entry point named
`LLVMFuzzerTestOneInput()`. When invoked, this executable either
searches for new test cases or runs an existing test case.

File `fuzz/bpf-object-fuzzer.c` defines an entry point for the robot:
- robot supplies bytes supposed to be an ELF file;
- wrapper invokes `bpf_object__open_mem()` to process these bytes.

File `scripts/build-fuzzers.sh` provides a recipe for fuzzer
infrastructure on how to build the executable described above (see
[here](https://github.com/google/oss-fuzz/tree/master/projects/libbpf)).

# Reproducing fuzzing errors

## Official way

OSS-Fuzz project describes error reproduction steps in the official
[documentation](https://google.github.io/oss-fuzz/advanced-topics/reproducing/).
Suppose you received an email linking to the fuzzer generated test
case, or got one as an artifact of the `CIFuzz` job (e.g. like
[here](https://github.com/libbpf/libbpf/actions/runs/16375110681)).
Actions to reproduce the error locally are:

```sh
git clone --depth=1 https://github.com/google/oss-fuzz.git
cd oss-fuzz
python infra/helper.py pull_images
python infra/helper.py build_image libbpf
python infra/helper.py build_fuzzers --sanitizer address libbpf <path-to-libbpf-checkout>
python infra/helper.py reproduce libbpf bpf-object-fuzzer <path-to-test-case>
```

`<path-to-test-case>` is usually a `crash-<many-hex-digits>` file w/o
extension, CI job wraps it into zip archive and attaches as an artifact.

To recompile after some fixes, repeat the `build_fuzzers` and
`reproduce` steps after modifying source code in
`<path-to-libbpf-checkout>`.

Note: the `build_fuzzers` step creates a binary
`build/out/libbpf/bpf-object-fuzzer`, it can be executed directly if
your environment is compatible.

## Simple way

From the project root:

```sh
SKIP_LIBELF_REBUILD=1 scripts/build-fuzzers.sh
out/bpf-object-fuzzer <path-to-test-case>
```

`out/bpf-object-fuzzer` is the fuzzer executable described earlier,
can be run with gdb etc.
