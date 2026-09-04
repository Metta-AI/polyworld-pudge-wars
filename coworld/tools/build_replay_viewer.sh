#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$1"
if [[ "${output_dir}" != /* && ! "${output_dir}" =~ ^[A-Za-z]:[\\/] ]] \
  || [[ "${output_dir}" == "/" || "${output_dir}" == "${repo_dir}" ]]; then
  echo "unsafe bundle output: ${output_dir}" >&2
  exit 1
fi

polyworld_root="${POLYWORLD_ROOT:-$(cd "${repo_dir}/.." && pwd)}"
if [[ ! -d "${polyworld_root}/examples/pudge_wars" ]]; then
  echo "polyworld root not found at ${polyworld_root}; set POLYWORLD_ROOT" >&2
  exit 1
fi
if [[ ! -d "${polyworld_root}/polyworld_data" && ! -d "${polyworld_root}/../polyworld_data" ]]; then
  echo "polyworld_data not found next to ${polyworld_root}; clone Metta-AI/polyworld-data" >&2
  exit 1
fi
if ! command -v emcc >/dev/null 2>&1; then
  echo "emcc is required to build the Pudge Wars replay viewer" >&2
  exit 1
fi
if ! command -v nim >/dev/null 2>&1; then
  echo "nim is required to build the Pudge Wars replay viewer" >&2
  exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

(
  cd "${polyworld_root}"
  nim c -d:emscripten examples/pudge_wars/pw.nim
)

src="${polyworld_root}/examples/pudge_wars/emscripten"
if [[ ! -f "${src}/pw.html" || ! -f "${src}/pw.wasm" || ! -f "${src}/pw.js" ]]; then
  echo "emscripten build did not produce pw.html/pw.wasm/pw.js in ${src}" >&2
  exit 1
fi

cp "${src}/pw.html" "${output_dir}/index.html"
cp "${src}/pw.js" "${output_dir}/pw.js"
cp "${src}/pw.wasm" "${output_dir}/pw.wasm"
if [[ -f "${src}/pw.data" ]]; then
  cp "${src}/pw.data" "${output_dir}/pw.data"
fi
