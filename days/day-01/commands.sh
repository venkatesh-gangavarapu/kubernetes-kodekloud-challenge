#!/usr/bin/env bash
# =============================================================================
# Day 01 — Kubernetes Challenge: Create a Pod
# Task: Create pod-nginx using nginx:latest, label app=nginx_app,
#       container named nginx-container
# Platform: KodeKloud lab | kubectl on jump-host
#
# LESSON FROM FIRST ATTEMPT:
#   kubectl run has no --container-name flag. It names the container after
#   the Pod (pod-nginx), not the value you want (nginx-container).
#   The correct imperative workflow: --dry-run=client -o yaml, patch, apply.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
# Always confirm kubectl can reach the cluster before doing anything.
# A misconfigured kubeconfig will fail silently in some environments.
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Check for a pre-existing pod-nginx ──────────────────────────────
# If a previous failed attempt left a pod behind, delete it first.
# kubectl delete on a non-existent pod returns exit code 1, so we suppress that.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get pod pod-nginx -n default &>/dev/null; then
  echo "Found existing pod-nginx — deleting it before recreating"
  kubectl delete pod pod-nginx -n default
  # Wait for deletion to complete before proceeding
  kubectl wait pod/pod-nginx --for=delete --timeout=30s -n default 2>/dev/null || true
else
  echo "No pre-existing pod-nginx found — proceeding"
fi
echo ""

# ─── STEP 3: Generate YAML skeleton via dry-run ──────────────────────────────
# --dry-run=client -o yaml prints the full resource object WITHOUT creating it.
# This is the standard CKA exam technique: let kubectl write the boilerplate,
# then patch the fields that can't be set via flags (like container name).
echo "=== Step 3: Generate pod-nginx.yaml via dry-run ==="
kubectl run pod-nginx \
  --image=nginx:latest \
  --labels="app=nginx_app" \
  --dry-run=client -o yaml > pod-nginx.yaml

echo "Generated pod-nginx.yaml:"
cat pod-nginx.yaml
echo ""

# ─── STEP 4: Patch the container name ────────────────────────────────────────
# The generated YAML has the container named "pod-nginx" (mirrors the Pod name).
# We need "nginx-container". The sed targets "  name: pod-nginx" (with leading
# spaces) to match ONLY the container entry, not the Pod metadata.name field.
echo "=== Step 4: Set container name to nginx-container ==="
sed -i 's/  name: pod-nginx/  name: nginx-container/' pod-nginx.yaml

echo "Patched pod-nginx.yaml:"
cat pod-nginx.yaml
echo ""

# ─── STEP 5: Apply the manifest ──────────────────────────────────────────────
# kubectl apply is idempotent — safe to run again if needed.
echo "=== Step 5: Apply pod-nginx.yaml ==="
kubectl apply -f pod-nginx.yaml
echo ""

# ─── STEP 6: Wait for Pod to be Ready ────────────────────────────────────────
# The node pulls nginx:latest from Docker Hub before starting the container.
# Wait up to 60 seconds before declaring failure.
echo "=== Step 6: Wait for Pod Ready condition ==="
kubectl wait pod/pod-nginx \
  --for=condition=Ready \
  --timeout=60s \
  -n default
echo ""

# ─── STEP 7: Verify STATUS and READY ─────────────────────────────────────────
# STATUS=Running and READY=1/1 are both required.
# A Pod can be Running but 0/1 ready — check both columns.
echo "=== Step 7: Verify Pod status ==="
kubectl get pod pod-nginx -n default
echo ""
kubectl get pod pod-nginx -n default -o wide
echo ""

# ─── STEP 8: Verify labels ───────────────────────────────────────────────────
# Confirms app=nginx_app is set exactly as required.
# Wrong labels = Services that select nothing downstream.
echo "=== Step 8: Verify labels ==="
kubectl get pod pod-nginx -n default --show-labels
echo ""

# ─── STEP 9: Verify container name ───────────────────────────────────────────
# This is the check that caught the first attempt failure.
# jsonpath extracts exactly the container name from the spec.
# Expected output: nginx-container
echo "=== Step 9: Verify container name ==="
CONTAINER_NAME=$(kubectl get pod pod-nginx -n default \
  -o jsonpath='{.spec.containers[0].name}')
echo "Container name: ${CONTAINER_NAME}"

if [ "${CONTAINER_NAME}" == "nginx-container" ]; then
  echo "✅ Container name is correct: nginx-container"
else
  echo "❌ Container name MISMATCH: expected nginx-container, got ${CONTAINER_NAME}"
  exit 1
fi
echo ""

# ─── STEP 10: Full describe ───────────────────────────────────────────────────
# Shows image pull events, scheduling decisions, and any errors.
# First stop when a Pod is stuck in Pending or ImagePullBackOff.
echo "=== Step 10: Full describe ==="
kubectl describe pod pod-nginx -n default
echo ""

# ─── STEP 11: Container logs ─────────────────────────────────────────────────
# nginx prints its startup log immediately — confirms the container is healthy.
# -c flag is explicit even on single-container Pods: good habit.
echo "=== Step 11: Container logs ==="
kubectl logs pod-nginx -n default -c nginx-container
echo ""

echo "============================================"
echo "All verification steps passed."
echo "pod-nginx is Running with:"
echo "  label:          app=nginx_app"
echo "  container name: nginx-container"
echo "  image:          nginx:latest"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# kubectl delete pod pod-nginx -n default
# rm -f pod-nginx.yaml
