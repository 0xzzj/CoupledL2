#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TLTEST_HOME="${TLTEST_HOME:-$(cd "${REPO_DIR}/.." && pwd)/tl-test}"
OUT_ROOT="${OUT_ROOT:-${REPO_DIR}/tl-test-out}"
WORK_DIR="${OUT_ROOT}/l2l3l2"
THREADS="${THREADS:-1}"
SEED="${SEED:-1000}"
CYCLES="${CYCLES:-20000}"
WAVE_BEGIN="${WAVE_BEGIN:-0}"
WAVE_END="${WAVE_END:-${CYCLES}}"
FRESH=0
BUILD_ONLY=0
RUN_ONLY=0
VERBOSE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/run_tltest_tl2tl.sh [options]

This runs the pure TileLink TL2TL test path:
  CoupledL2 TestTop_L2L3L2: L1D0 -> L2_0 \
                                         L3
                              L1D1 -> L2_1 /

No CHI RTL is generated. The two tl-test coherent agents drive
master_port_0_0 and master_port_1_0, which is the useful setup for
Acquire / Probe / Release waveform screenshots.

Options:
  --fresh       Re-copy and patch ../tl-test into tl-test-out/l2l3l2.
  --build-only  Generate RTL and build tl-test, but do not run.
  --run-only    Reuse the existing build and only run simulation.
  --verbose     Pass -v to tl-test so transaction logs include Acquire/Probe/Release.
  -h, --help    Show this help.

Environment:
  TLTEST_HOME   Path to tl-test. Default: ../tl-test
  OUT_ROOT      Output root. Default: ./tl-test-out
  THREADS       CMake/Verilator build threads. Default: 1
  SEED          tl-test random seed. Default: 1000
  CYCLES        Simulation cycles. Default: 20000
  WAVE_BEGIN    First cycle to dump. Default: 0
  WAVE_END      Last cycle to dump. Default: CYCLES

Outputs:
  tl-test-out/l2l3l2/run.log
  tl-test-out/l2l3l2/build/*.fst
  A terminal PASS banner when tl-test finishes successfully.
EOF
}

die() {
  echo "[tl2tl-test] error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)
      FRESH=1
      shift
      ;;
    --build-only)
      BUILD_ONLY=1
      shift
      ;;
    --run-only)
      RUN_ONLY=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "${BUILD_ONLY}" == "0" || "${RUN_ONLY}" == "0" ]] || die "--build-only and --run-only cannot be used together"

check_inputs() {
  need_cmd make
  need_cmd cmake
  need_cmd verilator
  need_cmd rsync
  need_cmd perl
  [[ -f "${TLTEST_HOME}/CMakeLists.txt" ]] || die "TLTEST_HOME does not look like tl-test: ${TLTEST_HOME}"
  [[ -f "${TLTEST_HOME}/Emu/Emu.cpp" ]] || die "missing tl-test Emu/Emu.cpp under ${TLTEST_HOME}"
}

copy_tltest() {
  if [[ "${FRESH}" == "1" || ! -d "${WORK_DIR}/src" ]]; then
    mkdir -p "${WORK_DIR}"
    rm -rf "${WORK_DIR}/src" "${WORK_DIR}/build"
    rsync -a "${TLTEST_HOME}/" "${WORK_DIR}/src/"
  fi
}

patch_tltest_copy() {
  local src="${WORK_DIR}/src"

  perl -0pi -e 's/NR_CAGENTS = 1/NR_CAGENTS = 2/' "${src}/Utils/Common.h"

  perl -0pi -e '
    s/#include "verilated_vcd_c\.h"/#include "verilated_fst_c.h"/;
    s/VerilatedVcdC\* tfp;/VerilatedFstC* tfp;/;
    s/"\.vcd"/".fst"/g;
    s/new VerilatedVcdC/new VerilatedFstC/;
  ' "${src}/Emu/Emu.h" "${src}/Emu/Emu.cpp"

  perl -0pi -e '
    s/&\(dut_ptr->(master_port_[01]_0_[acd]_bits_data)\)/dut_ptr->$1.data()/g;
    s/&\(dut_ptr->(master_port_[01]_0_b_bits_data)\[0\]\)/dut_ptr->$1.data()/g;
  ' "${src}/Emu/Emu.cpp"

  cat > "${src}/Emu/CMakeLists.txt" <<'EOF'
if(DEFINED CHISELDB)
    add_library(Emu Emu.h Emu.cpp
        ${DUT_DIR}/chisel_db.cpp
        ${DUT_DIR}/chisel_db.h
        ${DUT_DIR}/perfCCT.cpp
        ${DUT_DIR}/perfCCT.h)
else()
    add_library(Emu Emu.h Emu.cpp)
endif()

if(DEFINED TRACE)
    set(ARG_TRACE TRACE_FST)
endif()
if(DEFINED THREAD)
    set(ARG_THREAD ${THREAD})
else()
    set(ARG_THREAD 1)
endif()
if(DEFINED CHISELDB)
    set(ARG_CHISELDB -DENABLE_CHISEL_DB)
endif()

file(GLOB DBWRITER "${DUT_DIR}/*Writer.v")
if(DBWRITER AND NOT DEFINED CHISELDB)
    message(FATAL_ERROR "ChiselDB found! requires -DCHISELDB=1")
endif()

file(GLOB DUT_SOURCES "${DUT_DIR}/*.sv" "${DUT_DIR}/*.v")
list(LENGTH DUT_SOURCES DUT_SOURCE_COUNT)
if(DUT_SOURCE_COUNT EQUAL 0)
    message(FATAL_ERROR "No Verilog/SystemVerilog sources found in ${DUT_DIR}")
endif()

verilate(Emu
    SOURCES ${DUT_SOURCES}
    INCLUDE_DIRS "${DUT_DIR}"
    PREFIX VTestTop
    TOP_MODULE TestTop
    ${ARG_TRACE}
    THREADS ${ARG_THREAD}
    VERILATOR_ARGS
        -Wno-fatal
        -Wno-WIDTH
        -Wno-PINMISSING
        -DSIM_TOP_MODULE_NAME=TestTop
        ${ARG_CHISELDB}
)
EOF

  perl -0pi -e '
    s/find_package\(SQLite3\)/find_package(SQLite3)\nfind_library(LZ4_LIBRARY lz4)/;
    s/Threads::Threads \$\{SQLite3_LIBRARIES\}/Threads::Threads \$\{SQLite3_LIBRARIES\} \$\{LZ4_LIBRARY\}/g;
    s/Fuzzer \$\{SQLite3_LIBRARIES\}/Fuzzer \$\{SQLite3_LIBRARIES\} \$\{LZ4_LIBRARY\}/g;
  ' "${src}/CMakeLists.txt"
}

generate_dut() {
  echo "[tl2tl-test] generating pure TileLink TestTop_L2L3L2"
  make -C "${REPO_DIR}" clean
  make -C "${REPO_DIR}" compile
  make -C "${REPO_DIR}" test-top-l2l3l2
}

build_tltest() {
  echo "[tl2tl-test] building tl-test in ${WORK_DIR}/build"
  cmake "${WORK_DIR}/src" -B "${WORK_DIR}/build" \
    -DDUT_DIR="${REPO_DIR}/build" \
    -DTRACE=1 \
    -DCHISELDB=1 \
    -DTHREAD="${THREADS}"
  cmake --build "${WORK_DIR}/build" --parallel "${THREADS}"
}

run_tltest() {
  echo "[tl2tl-test] running seed=${SEED}, cycles=${CYCLES}, wave=${WAVE_BEGIN}..${WAVE_END}"
  local args=(
    -s "${SEED}"
    -c "${CYCLES}"
    -b "${WAVE_BEGIN}"
    -e "${WAVE_END}"
  )
  if [[ "${VERBOSE}" == "1" ]]; then
    args+=(-v)
  fi
  (
    cd "${WORK_DIR}/build"
    ./tlc_test "${args[@]}"
  ) 2>&1 | tee "${WORK_DIR}/run.log"
}

check_pass() {
  if grep -q '^Finished$' "${WORK_DIR}/run.log"; then
    {
      echo
      echo "[tl2tl-test] ========================================"
      echo "[tl2tl-test] TL2TL TEST PASS"
      echo "[tl2tl-test] seed=${SEED} cycles=${CYCLES} wave=${WAVE_BEGIN}..${WAVE_END}"
      echo "[tl2tl-test] ========================================"
    } | tee -a "${WORK_DIR}/run.log"
  else
    die "tl-test did not print Finished; see ${WORK_DIR}/run.log"
  fi
}

print_result() {
  echo
  echo "[tl2tl-test] work dir: ${WORK_DIR}"
  echo "[tl2tl-test] log:      ${WORK_DIR}/run.log"
  echo "[tl2tl-test] waves:"
  if [[ -d "${WORK_DIR}/build" ]]; then
    find "${WORK_DIR}/build" -maxdepth 1 -name '*.fst' -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr \
      | sed 's/^[^ ]* //'
  fi
}

main() {
  check_inputs
  export CCACHE_DISABLE="${CCACHE_DISABLE:-1}"
  mkdir -p "${OUT_ROOT}"
  copy_tltest
  patch_tltest_copy

  if [[ "${RUN_ONLY}" == "0" ]]; then
    generate_dut 2>&1 | tee "${WORK_DIR}/generate.log"
    build_tltest 2>&1 | tee "${WORK_DIR}/build.log"
  fi

  if [[ "${BUILD_ONLY}" == "0" ]]; then
    run_tltest
    check_pass
  fi

  print_result
}

main "$@"
