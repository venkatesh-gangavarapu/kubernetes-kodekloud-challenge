#!/usr/bin/env bash
# =============================================================================
# Day 03 — Kubernetes Challenge: Namespaces + Pod Deployment
# Task: Create namespace 'dev', deploy pod 'dev-nginx-pod' using nginx:latest
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY LESSON FROM DAY 01 + 02:
#   Always pass -n <namespace> explicitly on every kubectl command.
#   Without it, kubectl targets the kubeconfig default namespace (usually
#   'default') — the Pod lands in the wrong place and the validator finds nothing.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Check existing namespaces ───────────────────────────────────────
# Know the starting state. The system namespaces (default, kube-system,
# kube-public, kube-node-lease) are always present. 'dev' should not be yet.
echo "=== Step 2: Existing namespaces ==="
kubectl get namespaces
echo ""

# ─── STEP 3: Clean up any previous attempt ───────────────────────────────────
# If 'dev' namespace already exists from a failed run, we can reuse it or
# delete it and start fresh. We delete and recreate for a clean state.
# WARNING: 'kubectl delete namespace' cascades — everything inside is deleted.
echo "=== Step 3: Clean up any previous attempt ==="
if kubectl get namespace dev &>/dev/null; then
  echo "Namespace 'dev' already exists — deleting for a clean start"
  kubectl delete namespace dev
  echo "Waiting for namespace to fully terminate..."
  # Namespace termination is async — wait until it disappears
  while kubectl get namespace dev &>/dev/null; do sleep 2; done
  echo "Namespace 'dev' fully terminated"
else
  echo "No pre-existing 'dev' namespace — proceeding"
fi
echo ""

# ─── STEP 4: Create the namespace ────────────────────────────────────────────
# Namespace creation must happen BEFORE any resources are deployed into it.
# If the namespace doesn't exist when you apply a Pod manifest that references
# it, kubectl will reject with: namespace "dev" not found
echo "=== Step 4: Create namespace 'dev' ==="
kubectl create namespace dev
echo ""

# ─── STEP 5: Verify the namespace is Active ──────────────────────────────────
# A namespace can be in 'Active' or 'Terminating' state.
# Resources can only be created in an 'Active' namespace.
echo "=== Step 5: Verify namespace status ==="
kubectl get namespace dev
echo ""

# ─── STEP 6: Generate Pod manifest via dry-run ───────────────────────────────
# Passing -n dev here is critical — it sets metadata.namespace: dev in the
# generated YAML. Without -n, the manifest targets 'default'.
# This task doesn't require a custom container name, so no sed patch needed
# (unlike Day 01 where we patched pod-nginx → nginx-container).
echo "=== Step 6: Generate dev-nginx-pod.yaml via dry-run ==="
kubectl run dev-nginx-pod \
  --image=nginx:latest \
  --dry-run=client -o yaml \
  -n dev > dev-nginx-pod.yaml

echo "Generated manifest:"
cat dev-nginx-pod.yaml
echo ""

# ─── STEP 7: Apply the Pod manifest ──────────────────────────────────────────
echo "=== Step 7: Apply dev-nginx-pod.yaml ==="
kubectl apply -f dev-nginx-pod.yaml
echo ""

# ─── STEP 8: Wait for the Pod to be Ready ────────────────────────────────────
# Always wait for the Ready condition before running verification commands.
# nginx:latest needs to be pulled on the node — allow 60 seconds.
echo "=== Step 8: Wait for Pod Ready condition ==="
kubectl wait pod/dev-nginx-pod \
  --for=condition=Ready \
  --timeout=60s \
  -n dev
echo ""

# ─── STEP 9: Verify Pod status ───────────────────────────────────────────────
# The -n dev flag is mandatory here — without it, kubectl looks in 'default'
# and shows nothing, making it look like the Pod doesn't exist.
echo "=== Step 9: Verify Pod status ==="
kubectl get pod dev-nginx-pod -n dev
echo ""
kubectl get pod dev-nginx-pod -n dev -o wide
echo ""

# ─── STEP 10: Verify namespace in Pod metadata ───────────────────────────────
# Confirms the Pod actually landed in 'dev', not 'default'.
echo "=== Step 10: Verify Pod namespace ==="
NS=$(kubectl get pod dev-nginx-pod -n dev \
  -o jsonpath='{.metadata.namespace}')
echo "Pod namespace: ${NS}"

if [ "${NS}" == "dev" ]; then
  echo "✅ Pod is in the correct namespace: dev"
else
  echo "❌ Namespace mismatch: expected dev, got ${NS}"
  exit 1
fi
echo ""

# ─── STEP 11: Verify image tag ────────────────────────────────────────────────
# Confirm nginx:latest is set exactly as required.
echo "=== Step 11: Verify image tag ==="
IMAGE=$(kubectl get pod dev-nginx-pod -n dev \
  -o jsonpath='{.spec.containers[0].image}')
echo "Image: ${IMAGE}"

if [ "${IMAGE}" == "nginx:latest" ]; then
  echo "✅ Image tag is correct: nginx:latest"
else
  echo "❌ Image mismatch: expected nginx:latest, got ${IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 12: Cross-namespace visibility check ────────────────────────────────
# Shows the Pod appears when querying all namespaces.
# Also confirms nothing accidentally landed in 'default'.
echo "=== Step 12: Cross-namespace pod view ==="
kubectl get pods -A | grep -E "NAMESPACE|dev-nginx"
echo ""

# ─── STEP 13: Full describe ───────────────────────────────────────────────────
echo "=== Step 13: Full describe ==="
kubectl describe pod dev-nginx-pod -n dev
echo ""

echo "============================================"
echo "All verification steps passed."
echo "Namespace 'dev' created."
echo "Pod dev-nginx-pod is Running in namespace dev."
echo "  image: nginx:latest"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting the namespace cascades — the Pod is deleted along with it.
# kubectl delete namespace dev
# rm -f dev-namespace.yaml dev-nginx-pod.yaml
