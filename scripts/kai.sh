#!/usr/bin/env bash
# Run one portfolio prompt through kubectl-ai and save the resulting manifest.
#   scripts/kai.sh generate <name>  -> yaml/<name>.yaml
#   scripts/kai.sh analyse  <name>  -> yaml/<name>.fixed.yaml   (input: yaml/original/<name>.yaml)
set -euo pipefail

mode=${1:?usage: kai.sh generate|analyse <name>}
name=${2:?usage: kai.sh generate|analyse <name>}
root=$(cd "$(dirname "$0")/.." && pwd)
model=${KAI_MODEL:-gemini-3.8-flash}
k8s_version=${K8S_VERSION:-1.34.0}

: "${GEMINI_API_KEY:?export GEMINI_API_KEY first}"
: "${KUBECONFIG:?point KUBECONFIG at a throwaway cluster (e.g. kind) - kubectl-ai reads cluster state}"

# kubectl-ai runs read-only kubectl calls without asking: refuse to start unless the
# kubeconfig holds exactly one kind context.
for tool in kubectl kubeconform; do
  command -v "$tool" >/dev/null || { echo "$tool not found in PATH" >&2; exit 1; }
done

contexts=$(kubectl config get-contexts -o name)
if [[ $(wc -l <<<"$contexts") -ne 1 || $contexts != kind-* ]]; then
  echo "refusing: KUBECONFIG must contain exactly one kind-* context, got: $contexts" >&2
  exit 1
fi

case $mode in
  generate)
    prompt="$root/prompts/generate/$name.md"
    target="$root/yaml/$name.yaml"
    query=$(cat "$root/prompts/_system.md" - "$prompt" <<<"")
    ;;
  analyse)
    prompt="$root/prompts/analyse/$name.md"
    target="$root/yaml/$name.fixed.yaml"
    original="$root/yaml/original/$name.yaml"
    query=$(printf '%s\n\n%s\n\n%s\n\n--- MANIFEST ---\n# file: %s\n%s\n' \
      "$(cat "$root/prompts/_system.md")" "$(cat "$root/prompts/_analyse.md")" \
      "$(cat "$prompt")" "$name.yaml" "$(cat "$original")")
    ;;
  *) echo "unknown mode: $mode" >&2; exit 1 ;;
esac
# A missing file inside the analyse printf would not stop set -e: check before spending a request.
for f in "$prompt" "${original:-$prompt}"; do
  [[ -f $f ]] || { echo "no such file: $f" >&2; exit 1; }
done

mkdir -p "$root/out"
raw="$root/out/$mode-$name.raw"

# stdin must be closed, otherwise kubectl-ai --quiet waits for more input.
# The trace (default /tmp/kubectl-ai-trace.txt, world-readable) contains the API key: disable it.
run_model() {
  kubectl ai --quiet --model "$model" --trace-path /dev/null "$query" \
    </dev/null >"$raw" 2>"$root/out/$mode-$name.err"
}

# With stdout redirected, kubectl-ai renders the fenced block without fences, indented by
# 4 spaces and right-padded; lines longer than ~72 chars are wrapped with a 2-space indent.
# Strip padding, leading blank lines and the indent; reject wrapped or truncated output.
extract() {
  local body
  body=$(sed -e 's/[[:space:]]*$//' "$raw" | sed -e '/./,$!d')
  if grep -qvE '^(    |$)' <<<"$body"; then
    echo "not a single code block (wrapped lines or prose)"; return 1
  fi
  body=$(sed -e 's/^    //' <<<"$body")
  if [[ $mode == analyse ]]; then
    # analyse answers are long and sometimes cut off mid-file; the prompt demands an end marker
    if [[ $(tail -n 1 <<<"$body") != "# end of manifest" ]]; then
      echo "truncated (no end marker)"; return 1
    fi
    body=$(sed -e '$d' <<<"$body")
  fi
  printf '%s\n' "$body" >"$tmp"
  grep -q '^kind:' "$tmp" || { echo "no Kubernetes object in the answer"; return 1; }
  kubeconform -strict -summary -kubernetes-version "$k8s_version" "$tmp" >&2 || {
    echo "kubeconform failed"; return 1; }
}

tmp=$(mktemp --suffix=.yaml)  # kubeconform skips files without a .yaml extension
trap 'rm -f "$tmp"' EXIT

# Retry cut-off or malformed answers. Failed requests (busy model, timeouts) still count
# against the free-tier daily quota, so a busy model gets one retry and then exit 3 -
# retrying through an overload burns the whole quota. Quota gone -> exit 2 at once.
busy=0
for attempt in 1 2 3; do
  if run_model; then
    if reason=$(extract); then
      mv "$tmp" "$target"
      echo "saved $target"
      exit 0
    fi
  elif grep -q 'PerDay\|per day' "$raw"; then
    echo "daily quota exhausted for $model:" >&2
    grep -o 'Please retry in [^,]*' "$raw" | head -1 >&2
    exit 2
  elif grep -qE 'Error (503|429)|deadline exceeded|Client.Timeout' "$raw"; then
    reason="model busy or timed out"
    busy=$((busy + 1))
    if [[ $busy -ge 2 ]]; then
      echo "$mode/$name: $model still busy, try later or another KAI_MODEL" >&2
      exit 3
    fi
  else
    echo "kubectl-ai failed for $mode/$name:" >&2
    cat "$raw" >&2
    exit 1
  fi
  echo "$mode/$name attempt $attempt: $reason" >&2
  [[ $attempt -lt 3 ]] && sleep 60
done
echo "giving up on $mode/$name, last raw output: $raw" >&2
exit 1
