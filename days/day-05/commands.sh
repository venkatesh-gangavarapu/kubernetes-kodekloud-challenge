#!/usr/bin/env bash
# =============================================================================
# Day 05 — Kubernetes Challenge: Rolling Update
# Task: Update nginx-deployment to use image nginx:1.18
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY INSIGHT:
#   kubectl set image requires the CONTAINER NAME, not the deployment name.
#   Never assume the container name — always inspect it first.
#   A wrong container name produces no update and no clear error in some versions.
#   Pattern: inspect → update → block on rollout status → verify image.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Confirm the deployment exists ───────────────────────────────────
# The task says nginx-deployment already exists — but always verify before
# attempting an update. Updating a non-existent deployment fails silently
# in some kubectl versions or returns a confusing error.
echo "=== Step 2: Confirm nginx-deployment exists ==="
kubectl get deployment nginx-deployment -n default
echo ""

# ─── STEP 3: Inspect the current state before touching anything ──────────────
# Document the pre-update state: current image, replica count, ready status.
# This is the baseline you compare against post-update to confirm the change.
echo "=== Step 3: Pre-update state ==="
echo "Current image:"
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

echo "Current replica state:"
kubectl get deployment nginx-deployment -n default
echo ""

echo "Current pods:"
kubectl get pods -n default
echo ""

# ─── STEP 4: Discover the container name ─────────────────────────────────────
# CRITICAL: kubectl set image needs the container name, not the deployment name.
# Store it in a variable so the set image command uses the real value.
# If the deployment has multiple containers, inspect all of them:
#   kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[*].name}'
echo "=== Step 4: Discover container name ==="
CONTAINER=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER}"
echo ""

# ─── STEP 5: Execute the rolling update ──────────────────────────────────────
# kubectl set image triggers the rolling update immediately.
# The Deployment controller creates a new ReplicaSet with the updated image,
# then incrementally scales up new Pods and scales down old ones.
# Old ReplicaSet is kept at 0 replicas after completion — required for rollback.
echo "=== Step 5: Execute rolling update to nginx:1.18 ==="
kubectl set image deployment/nginx-deployment \
  "${CONTAINER}=nginx:1.18" \
  -n default

echo "Rolling update triggered."
echo ""

# ─── STEP 6: Monitor rollout in real time ────────────────────────────────────
# rollout status BLOCKS until the update is fully complete.
# Do not skip this step and move to verification — the update is async.
# If it hangs: check kubectl get pods for ImagePullBackOff or CrashLoopBackOff.
echo "=== Step 6: Watch rollout status (blocking) ==="
kubectl rollout status deployment/nginx-deployment \
  -n default \
  --timeout=120s
echo ""

# ─── STEP 7: Verify deployment is fully Ready ────────────────────────────────
# READY should match DESIRED. UP-TO-DATE confirms all replicas run the new image.
echo "=== Step 7: Post-update deployment status ==="
kubectl get deployment nginx-deployment -n default
echo ""

# ─── STEP 8: Verify all pods are operational ─────────────────────────────────
# Every pod should show STATUS=Running and READY=1/1.
# Any pod in ImagePullBackOff, CrashLoopBackOff, or Pending needs investigation.
echo "=== Step 8: Verify all pods are Running ==="
kubectl get pods -n default
echo ""

# ─── STEP 9: Confirm the new image is live ───────────────────────────────────
# jsonpath into the deployment spec to confirm nginx:1.18 is the current image.
echo "=== Step 9: Verify image updated to nginx:1.18 ==="
NEW_IMAGE=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Current image: ${NEW_IMAGE}"

if [ "${NEW_IMAGE}" == "nginx:1.18" ]; then
  echo "✅ Image successfully updated to nginx:1.18"
else
  echo "❌ Image mismatch: expected nginx:1.18, got ${NEW_IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 10: Check rollout history ──────────────────────────────────────────
# Shows the revision history — each rolling update creates a new revision.
# Rollback targets a specific revision number from this list.
echo "=== Step 10: Rollout history (audit trail) ==="
kubectl rollout history deployment/nginx-deployment -n default
echo ""

# ─── STEP 11: Inspect ReplicaSets ────────────────────────────────────────────
# After the update, two ReplicaSets exist:
#   Old RS: DESIRED=0, CURRENT=0, READY=0  (kept for rollback)
#   New RS: DESIRED=N, CURRENT=N, READY=N  (active)
echo "=== Step 11: ReplicaSet state post-update ==="
kubectl get replicaset -n default
echo ""

# ─── STEP 12: Full describe ───────────────────────────────────────────────────
# Events section shows the scale-up/scale-down sequence of the rolling update.
echo "=== Step 12: Full describe ==="
kubectl describe deployment nginx-deployment -n default
echo ""

echo "============================================"
echo "Rolling update complete."
echo "Deployment nginx-deployment is running nginx:1.18"
echo "All pods are operational."
echo "============================================"

# ─── ROLLBACK (commented — use if update needs to be reversed) ───────────────
# Scales up the old ReplicaSet, scales down the new one.
# No image re-pull required — uses the cached ReplicaSet spec.
# kubectl rollout undo deployment/nginx-deployment -n default
# kubectl rollout status deployment/nginx-deployment -n default
