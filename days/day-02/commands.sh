#!/usr/bin/env bash
# =============================================================================
# Day 02 — Kubernetes Challenge: Create a Deployment
# Task: Create a Deployment named nginx using nginx:latest
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY LESSON FROM DAY 01:
#   kubectl run creates a bare Pod, NOT a Deployment.
#   For Deployments, use: kubectl create deployment
#   Always use --dry-run=client -o yaml to generate a manifest first —
#   gives you version control and full spec visibility before applying.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
# Confirm kubectl can reach the cluster from the jump-host.
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
# If a previous run left a deployment behind, delete it cleanly.
# The Deployment deletion cascades: ReplicaSet and Pods are garbage-collected.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get deployment nginx -n default &>/dev/null; then
  echo "Found existing deployment nginx — deleting before recreating"
  kubectl delete deployment nginx -n default
  echo "Waiting for Pods to terminate..."
  sleep 5
else
  echo "No pre-existing deployment found — proceeding"
fi
echo ""

# ─── STEP 3: Generate the Deployment manifest via dry-run ────────────────────
# kubectl create deployment is purpose-built for Deployments (unlike kubectl run).
# --dry-run=client -o yaml prints the full object without touching the cluster.
# This gives us a manifest to inspect, edit if needed, and version-control.
echo "=== Step 3: Generate nginx-deployment.yaml via dry-run ==="
kubectl create deployment nginx \
  --image=nginx:latest \
  --dry-run=client -o yaml > nginx-deployment.yaml

echo "Generated manifest:"
cat nginx-deployment.yaml
echo ""

# ─── STEP 4: Apply the manifest ──────────────────────────────────────────────
# kubectl apply is idempotent — safe to re-run if something fails mid-way.
# kubectl create would fail with "already exists" on a second run.
echo "=== Step 4: Apply nginx-deployment.yaml ==="
kubectl apply -f nginx-deployment.yaml
echo ""

# ─── STEP 5: Wait for rollout to complete ────────────────────────────────────
# kubectl rollout status blocks until all replicas are available and updated.
# This is the authoritative check — more reliable than polling kubectl get.
echo "=== Step 5: Wait for rollout to complete ==="
kubectl rollout status deployment/nginx -n default
echo ""

# ─── STEP 6: Verify the Deployment ──────────────────────────────────────────
# READY=1/1, UP-TO-DATE=1, AVAILABLE=1 — all three columns matter.
echo "=== Step 6: Verify Deployment ==="
kubectl get deployment nginx -n default
echo ""

# ─── STEP 7: Verify the ReplicaSet ───────────────────────────────────────────
# The Deployment auto-created a ReplicaSet. Its name = nginx-<pod-template-hash>.
# You should see DESIRED=1, CURRENT=1, READY=1.
# Never edit this ReplicaSet directly — the Deployment owns and overwrites it.
echo "=== Step 7: Verify ReplicaSet (auto-created by Deployment) ==="
kubectl get replicaset -n default
echo ""

# ─── STEP 8: Verify the Pod ──────────────────────────────────────────────────
# Pod name follows the chain: nginx-<rs-hash>-<pod-hash>
# This is the actual workload created at the bottom of the ownership chain.
echo "=== Step 8: Verify Pod ==="
kubectl get pods -n default
echo ""
kubectl get pods -n default -o wide
echo ""

# ─── STEP 9: Verify the image tag ────────────────────────────────────────────
# jsonpath drills into the Deployment's pod template spec to confirm the image.
# Expected: nginx:latest
echo "=== Step 9: Verify image tag ==="
IMAGE=$(kubectl get deployment nginx -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: ${IMAGE}"

if [ "${IMAGE}" == "nginx:latest" ]; then
  echo "✅ Image tag is correct: nginx:latest"
else
  echo "❌ Image mismatch: expected nginx:latest, got ${IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 10: Full describe ───────────────────────────────────────────────────
# Shows rolling update strategy, selector, pod template, and events.
# Events section shows pull and scheduling history — useful for debugging.
echo "=== Step 10: Full describe ==="
kubectl describe deployment nginx -n default
echo ""

echo "============================================"
echo "All verification steps passed."
echo "Deployment nginx is running with:"
echo "  image:    nginx:latest"
echo "  replicas: 1/1 ready"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting the Deployment cascades: ReplicaSet and Pods are garbage-collected.
# kubectl delete deployment nginx -n default
# rm -f nginx-deployment.yaml
