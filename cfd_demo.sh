#!/usr/bin/env bash
set -euo pipefail

ROOT_RENDERER="/home/io/projects/learn_erl/scenic_renderer_native"
ROOT_VIZ="/home/io/projects/learn_erl/pymc/exmc_viz"
ROOT_CFD="/home/io/projects/cdf/openfoam/cdf_beam"

RENDERER_BIN="$ROOT_RENDERER/build/examples/glfw_standalone/scenic_standalone"

cleanup() {
  if [[ -n "${CFD_PID:-}" ]]; then kill "$CFD_PID" 2>/dev/null || true; fi
  if [[ -n "${VIZ_PID:-}" ]]; then kill "$VIZ_PID" 2>/dev/null || true; fi
  if [[ -n "${RENDERER_PID:-}" ]]; then kill "$RENDERER_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

if [[ ! -x "$RENDERER_BIN" ]]; then
  echo "Building scenic_renderer_native..."
  mkdir -p "$ROOT_RENDERER/build"
  pushd "$ROOT_RENDERER/build" >/dev/null
  cmake ..
  make
  popd >/dev/null
fi

echo "Starting renderer on :4000..."
"$RENDERER_BIN" -p 4000 &
RENDERER_PID=$!

sleep 1

echo "Starting ExmcViz CFD dashboard (remote driver)..."
pushd "$ROOT_VIZ" >/dev/null
iex -S mix -e "ExmcViz.cfd_dashboard(host: \"127.0.0.1\", port: 4000, metrics_port: 4100)" &
VIZ_PID=$!
popd >/dev/null

sleep 2

echo "Running CFD case and streaming metrics..."
pushd "$ROOT_CFD" >/dev/null
CDF_VIZ_HOST=127.0.0.1 CDF_VIZ_PORT=4100 \
  mix run -e "{:ok, _}=CdfBeam.load_case(\"examples/pitzDaily_test.cfd\", partitions: 2); CdfBeam.SolverController.run_sync()" &
CDF_PID=$!
popd >/dev/null

echo "Demo running. Press Ctrl+C to stop."
wait
