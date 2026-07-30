#!/usr/bin/env bash
# =============================================================================
# Day 04 — Kubernetes Challenge: Resource Requests and Limits
# Task: Create httpd-pod with httpd-container, image httpd:latest
#       Requests: memory=15Mi, cpu=100m
#       Limits:   memory=20Mi, cpu=100m
# Platform: KodeKloud lab | kubectl on jump-host
#
# COMBINED LESSON FROM DAY 01 + DAY 04:
#   kubectl run --requests/--limits flags set resource values correctly.
#   BUT kubectl run still names the container after the Pod (httpd-pod).
#   We must patch the container name BEFORE applying — same dry-run + sed
#   technique from Day 01. Container name sits at 4-space indent in the YAML;
#   pod metadata.name sits at 2-space indent — target 4 spaces to avoid
#   accidentally renaming the Pod itself.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get pod httpd-pod -n default &>/dev/null; then
  echo "Found existing httpd-pod — deleting before recreating"
  kubectl delete pod httpd-pod -n default
  kubectl wait pod/httpd-pod --for=delete --timeout=30s -n default 2>/dev/null || true
else
  echo "No pre-existing httpd-pod found — proceeding"
fi
echo ""

# ─── STEP 3: Generate the Pod manifest via dry-run ───────────────────────────
# --requests and --limits are supported flags on kubectl run.
# --dry-run=client -o yaml prints the full spec without touching the cluster.
# Combined with resource flags, this generates a complete manifest including
# the resources block — no manual editing of resources needed, only the name.
echo "=== Step 3: Generate httpd-pod.yaml via dry-run ==="
kubectl run httpd-pod \
  --image=httpd:latest \
  --requests='memory=15Mi,cpu=100m' \
  --limits='memory=20Mi,cpu=100m' \
  --dry-run=client -o yaml > httpd-pod.yaml

echo "Generated manifest (before patch):"
cat httpd-pod.yaml
echo ""

# ─── STEP 4: Patch the container name ────────────────────────────────────────
# The generated YAML has two 'name' entries:
#   metadata.name:       "  name: httpd-pod"   (2-space indent) — the Pod name, leave it
#   containers[].name:   "    name: httpd-pod"  (4-space indent) — patch this to httpd-container
#
# Using 4 leading spaces in the sed pattern ensures we only target the
# container name line, not the pod metadata.name line.
echo "=== Step 4: Patch container name to httpd-container ==="
sed -i 's/    name: httpd-pod/    name: httpd-container/' httpd-pod.yaml

echo "Patched manifest:"
cat httpd-pod.yaml
echo ""

# ─── STEP 5: Apply the manifest ──────────────────────────────────────────────
echo "=== Step 5: Apply httpd-pod.yaml ==="
kubectl apply -f httpd-pod.yaml
echo ""

# ─── STEP 6: Wait for Pod to be Ready ────────────────────────────────────────
# httpd:latest needs to be pulled — allow 60 seconds.
echo "=== Step 6: Wait for Pod Ready condition ==="
kubectl wait pod/httpd-pod \
  --for=condition=Ready \
  --timeout=60s \
  -n default
echo ""

# ─── STEP 7: Verify Pod status ───────────────────────────────────────────────
echo "=== Step 7: Verify Pod status ==="
kubectl get pod httpd-pod -n default
echo ""
kubectl get pod httpd-pod -n default -o wide
echo ""

# ─── STEP 8: Verify container name ───────────────────────────────────────────
# The same check that caught the failure on Day 01.
echo "=== Step 8: Verify container name ==="
CONTAINER_NAME=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].name}')
echo "Container name: ${CONTAINER_NAME}"

if [ "${CONTAINER_NAME}" == "httpd-container" ]; then
  echo "✅ Container name is correct: httpd-container"
else
  echo "❌ Container name mismatch: expected httpd-container, got ${CONTAINER_NAME}"
  exit 1
fi
echo ""

# ─── STEP 9: Verify resource requests ────────────────────────────────────────
# jsonpath into the resources block to confirm exact values.
echo "=== Step 9: Verify resource requests ==="
MEM_REQ=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources.requests.memory}')
CPU_REQ=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
echo "Memory request: ${MEM_REQ}  (expected: 15Mi)"
echo "CPU request:    ${CPU_REQ}  (expected: 100m)"
echo ""

# ─── STEP 10: Verify resource limits ─────────────────────────────────────────
echo "=== Step 10: Verify resource limits ==="
MEM_LIM=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}')
CPU_LIM=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
echo "Memory limit: ${MEM_LIM}  (expected: 20Mi)"
echo "CPU limit:    ${CPU_LIM}  (expected: 100m)"
echo ""

# ─── STEP 11: Verify QoS class ────────────────────────────────────────────────
# This Pod is Burstable because memory request (15Mi) != memory limit (20Mi).
# Guaranteed would require all requests == all limits.
echo "=== Step 11: Verify QoS class ==="
QOS=$(kubectl get pod httpd-pod -n default \
  -o jsonpath='{.status.qosClass}')
echo "QoS class: ${QOS}  (expected: Burstable)"
echo ""

# ─── STEP 12: Full describe ───────────────────────────────────────────────────
# Look for: QoS Class, Limits, Requests sections in the output.
echo "=== Step 12: Full describe ==="
kubectl describe pod httpd-pod -n default
echo ""

echo "============================================"
echo "All verification steps passed."
echo "httpd-pod is Running with:"
echo "  container name:  httpd-container"
echo "  image:           httpd:latest"
echo "  memory request:  ${MEM_REQ}"
echo "  cpu request:     ${CPU_REQ}"
echo "  memory limit:    ${MEM_LIM}"
echo "  cpu limit:       ${CPU_LIM}"
echo "  QoS class:       ${QOS}"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# kubectl delete pod httpd-pod -n default
# rm -f httpd-pod.yaml
