#!/usr/bin/env bash
# =============================================================================
# Day 11 — Kubernetes Challenge: Troubleshoot Multi-Container Pod
# Task: Fix pod 'webserver' (httpd-container + sidecar-container) to Running state
# Platform: KodeKloud lab | kubectl on jump-host
#
# TROUBLESHOOTING METHODOLOGY — always in this order:
#   1. GET   → what state is the pod in right now?
#   2. DESCRIBE → what events and container states explain that state?
#   3. LOGS  → what did the container output before failing?
#   4. FIX   → export YAML, edit root cause, delete, reapply
#   5. VERIFY → READY=2/2 + application accessible
#
# MOST LIKELY ROOT CAUSE:
#   sidecar-container using ubuntu:latest has no foreground command.
#   Ubuntu's default entrypoint (/bin/bash) exits immediately with no TTY.
#   → CrashLoopBackOff on the sidecar container.
#   Fix: add 'command: ["/bin/bash", "-c", "sleep infinity"]' to sidecar spec.
#
# NEVER: delete and recreate before reading the error — wastes lab time.
# ALWAYS: use --previous flag for CrashLoopBackOff log retrieval.
# =============================================================================
set -e

# ─── PHASE 1: INVESTIGATE ────────────────────────────────────────────────────

# ─── STEP 1: Confirm cluster access and pod existence ────────────────────────
echo "=== Step 1: Cluster access and pod state ==="
kubectl get nodes
echo ""
kubectl get pod webserver -n default
echo ""

# ─── STEP 2: Get detailed pod state — STATUS, READY count, node placement ────
echo "=== Step 2: Pod state detail ==="
kubectl get pod webserver -n default -o wide
echo ""

# ─── STEP 3: DESCRIBE — the most important troubleshooting command ────────────
# Read ALL sections:
#   Containers: → State, Last State, Reason, Exit Code for each container
#   Events:     → chronological record of scheduler + kubelet actions
# This tells you: CrashLoopBackOff? ImagePullBackOff? OOMKill? ConfigError?
echo "=== Step 3: kubectl describe pod webserver ==="
kubectl describe pod webserver -n default
echo ""

# ─── STEP 4: Read container logs ─────────────────────────────────────────────
# In CrashLoopBackOff the container keeps restarting.
# Current logs may be empty (just restarted). Use --previous for the crash evidence.
echo "=== Step 4: Container logs ==="
echo "--- httpd-container logs ---"
kubectl logs webserver -n default -c httpd-container || true
echo ""

echo "--- sidecar-container logs (current) ---"
kubectl logs webserver -n default -c sidecar-container || true
echo ""

echo "--- sidecar-container logs (previous run — crash evidence) ---"
kubectl logs webserver -n default -c sidecar-container --previous 2>/dev/null \
  || echo "No previous run logs (pod may not have restarted yet)"
echo ""

# ─── STEP 5: Export current broken pod spec ───────────────────────────────────
# This gives us the baseline YAML to edit and reapply.
# Must clean server-generated fields before reapplying.
echo "=== Step 5: Export pod spec to webserver-fix.yaml ==="
kubectl get pod webserver -n default -o yaml > webserver-raw.yaml
echo "Raw spec exported to webserver-raw.yaml"
echo ""

# ─── PHASE 2: FIX ────────────────────────────────────────────────────────────
# CONFIRMED ROOT CAUSE: httpd-container image tag is 'httpd:latests' (typo)
# instead of 'httpd:latest'. Docker Hub returns "not found" for that tag.
# The sidecar-container started successfully — it was never the problem.
# Events section confirmed: "Failed to pull image httpd:latests: not found"

# ─── STEP 6A: Fix — Option A (Fastest — image patch directly on the Pod) ─────
# kubectl set image works on a bare Pod for the image field.
# Since httpd-container is stuck in ImagePullBackOff (not running),
# the kubelet picks up the corrected image immediately and retries the pull.
echo "=== Step 6A: Patch image directly on the running pod ==="
kubectl set image pod/webserver httpd-container=httpd:latest -n default
echo "Image patched: httpd:latests → httpd:latest"
echo ""

# ─── STEP 6B: Fix — Option B (Universal — export, fix, delete, reapply) ──────
# Use this if Option A doesn't take effect or you need a clean reapply.
# Uncomment to use:
#
# echo "=== Step 6B: Export, fix, delete, reapply ==="
# kubectl get pod webserver -n default -o yaml > webserver-raw.yaml
# sed 's/httpd:latests/httpd:latest/g' webserver-raw.yaml \
#   | grep -v '^\s*resourceVersion:\|^\s*uid:\|^\s*selfLink:\|^status:' \
#   > webserver-fix.yaml
# kubectl delete pod webserver -n default
# kubectl wait pod/webserver --for=delete --timeout=30s -n default 2>/dev/null || true
# kubectl apply -f webserver-fix.yaml

# ─── STEP 7: Watch the image pull and container start ────────────────────────
# After the patch, the kubelet retries pulling httpd:latest.
# ImagePullBackOff clears, container starts, READY flips to 2/2.
echo "=== Step 7: Watch pod recover (Ctrl+C when READY=2/2) ==="
kubectl get pod webserver -n default -w &
WATCH_PID=$!
sleep 30
kill $WATCH_PID 2>/dev/null || true
echo ""

# ─── PHASE 3: VERIFY ─────────────────────────────────────────────────────────

# ─── STEP 10: Wait for pod to be Running ─────────────────────────────────────
echo "=== Step 10: Wait for pod Ready ==="
kubectl wait pod/webserver \
  --for=condition=Ready \
  --timeout=90s \
  -n default
echo ""

# ─── STEP 11: Confirm READY=2/2 ───────────────────────────────────────────────
# Both containers must be Running — not just one.
echo "=== Step 11: Verify READY=2/2 ==="
kubectl get pod webserver -n default
READY=$(kubectl get pod webserver -n default --no-headers | awk '{print $2}')
echo "Ready count: ${READY}  (expected: 2/2)"

if [ "${READY}" == "2/2" ]; then
  echo "✅ Both containers Running: READY=2/2"
else
  echo "❌ Not all containers ready: ${READY}"
  kubectl describe pod webserver -n default
  exit 1
fi
echo ""

# ─── STEP 12: Verify container images match task spec ─────────────────────────
echo "=== Step 12: Verify container images ==="
kubectl get pod webserver -n default \
  -o jsonpath='{range .spec.containers[*]}{.name}: {.image}{"\n"}{end}'
echo ""

# ─── STEP 13: Verify each container's logs ────────────────────────────────────
echo "=== Step 13: Verify container logs ==="
echo "--- httpd-container ---"
kubectl logs webserver -n default -c httpd-container | head -20
echo ""

echo "--- sidecar-container ---"
kubectl logs webserver -n default -c sidecar-container | head -10
echo ""

# ─── STEP 14: Verify application is accessible ────────────────────────────────
# Containers in the same pod share localhost — curl from sidecar reaches httpd.
echo "=== Step 14: Verify application accessible via sidecar curl ==="
kubectl exec webserver -n default -c sidecar-container \
  -- curl -s --max-time 5 http://localhost:80 | head -5
echo ""

# ─── STEP 15: Full describe — confirm clean state ─────────────────────────────
echo "=== Step 15: Full describe (confirm both containers healthy) ==="
kubectl describe pod webserver -n default
echo ""

echo "============================================"
echo "Troubleshooting complete."
echo "Pod webserver is Running with READY=2/2:"
echo "  httpd-container:   httpd:latest    → Running"
echo "  sidecar-container: ubuntu:latest   → Running (sleep infinity)"
echo "  Application:       accessible on port 80"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# kubectl delete pod webserver -n default
# rm -f webserver-raw.yaml webserver-fix.yaml
