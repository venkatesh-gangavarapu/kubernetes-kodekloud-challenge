#!/usr/bin/env bash
# =============================================================================
# Day 06 — Kubernetes Challenge: Deployment Rollback
# Task: Rollback nginx-deployment to the previous revision
# Platform: KodeKloud lab | kubectl on jump-host
#
# DIRECT CONTINUATION OF DAY 05:
#   Day 05 executed a rolling update (nginx:old → nginx:1.18).
#   Today a bug was found in that release — rollback to the previous revision.
#
# KEY INSIGHT:
#   rollout undo is NOT instant — it runs the same rolling update mechanism
#   in reverse. Old ReplicaSet (kept at 0 replicas after Day 05) scales back
#   up; current ReplicaSet scales back down. No image re-pull required.
#   Always inspect history BEFORE rolling back — never assume what "previous"
#   means without checking. Revision numbers shift after each rollback.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Confirm the deployment exists ───────────────────────────────────
echo "=== Step 2: Confirm nginx-deployment exists ==="
kubectl get deployment nginx-deployment -n default
echo ""

# ─── STEP 3: Document the current (buggy) state ──────────────────────────────
# Record the current image before rolling back — this is the baseline.
# Comparing pre-rollback vs post-rollback image confirms the operation worked.
echo "=== Step 3: Current (buggy) image ==="
CURRENT_IMAGE=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Current image (to be rolled back FROM): ${CURRENT_IMAGE}"
echo ""

echo "Current pods:"
kubectl get pods -n default
echo ""

# ─── STEP 4: Inspect the full rollout history ────────────────────────────────
# ALWAYS check history before rolling back.
# This shows available revision numbers — you must know what "previous" is
# before blindly executing rollout undo.
# CHANGE-CAUSE shows <none> unless --record or kubectl annotate was used.
echo "=== Step 4: Rollout history ==="
kubectl rollout history deployment/nginx-deployment -n default
echo ""

# ─── STEP 5: Inspect the target revision before rolling back ─────────────────
# --revision=1 shows the pod template of revision 1, including its image.
# Confirm this is the version you want restored before touching anything.
echo "=== Step 5: Inspect revision 1 (rollback target) ==="
kubectl rollout history deployment/nginx-deployment \
  --revision=1 \
  -n default
echo ""

# ─── STEP 6: Check current ReplicaSets ───────────────────────────────────────
# After Day 05's rolling update, two ReplicaSets exist:
#   Old RS: DESIRED=0 CURRENT=0 READY=0  (previous version — dormant)
#   New RS: DESIRED=N CURRENT=N READY=N  (current buggy version — active)
# rollout undo reverses this: old RS scales up, new RS scales down.
echo "=== Step 6: ReplicaSet state before rollback ==="
kubectl get replicaset -n default
echo ""

# ─── STEP 7: Execute the rollback ────────────────────────────────────────────
# rollout undo with no flags rolls back exactly one revision (previous).
# For a specific revision: kubectl rollout undo --to-revision=N
# This triggers a rolling update in reverse — not an instant swap.
echo "=== Step 7: Execute rollback ==="
kubectl rollout undo deployment/nginx-deployment -n default
echo "Rollback initiated."
echo ""

# ─── STEP 8: Block until rollback is complete ────────────────────────────────
# rollout undo is asynchronous. Never skip this step.
# If it times out: check kubectl get pods for ImagePullBackOff or OOMKilled.
echo "=== Step 8: Wait for rollback to complete (blocking) ==="
kubectl rollout status deployment/nginx-deployment \
  -n default \
  --timeout=120s
echo ""

# ─── STEP 9: Verify all pods are Running ─────────────────────────────────────
# Every pod should show STATUS=Running and READY=1/1.
echo "=== Step 9: Verify all pods are operational ==="
kubectl get pods -n default
echo ""

# ─── STEP 10: Confirm image reverted successfully ────────────────────────────
# jsonpath into the deployment spec confirms the image change took effect.
echo "=== Step 10: Verify image after rollback ==="
ROLLED_BACK_IMAGE=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image before rollback: ${CURRENT_IMAGE}"
echo "Image after rollback:  ${ROLLED_BACK_IMAGE}"

if [ "${ROLLED_BACK_IMAGE}" != "${CURRENT_IMAGE}" ]; then
  echo "✅ Rollback successful — image has changed to: ${ROLLED_BACK_IMAGE}"
else
  echo "❌ Image unchanged after rollback — investigate rollout history"
  exit 1
fi
echo ""

# ─── STEP 11: Check updated rollout history ───────────────────────────────────
# After rollback, revision numbers shift:
# The restored version becomes the NEW highest revision number.
# Revision 1 no longer exists as revision 1 — it is renumbered.
echo "=== Step 11: Rollout history post-rollback ==="
kubectl rollout history deployment/nginx-deployment -n default
echo ""

# ─── STEP 12: ReplicaSet state after rollback ────────────────────────────────
# After rollback, the two RS swap roles:
#   Previously-old RS: now DESIRED=N READY=N  (active — restored version)
#   Previously-active RS: now DESIRED=0 READY=0  (dormant — buggy version)
echo "=== Step 12: ReplicaSet state after rollback ==="
kubectl get replicaset -n default
echo ""

# ─── STEP 13: Full describe ───────────────────────────────────────────────────
# Events section shows the scale-up/scale-down sequence of the rollback.
echo "=== Step 13: Full describe ==="
kubectl describe deployment nginx-deployment -n default
echo ""

echo "============================================"
echo "Rollback complete."
echo "nginx-deployment restored from: ${CURRENT_IMAGE}"
echo "                            to: ${ROLLED_BACK_IMAGE}"
echo "All pods are operational."
echo "============================================"

# ─── RE-ROLLBACK NOTE ────────────────────────────────────────────────────────
# If you need to go back AGAIN (e.g. the rollback itself is wrong):
# Revision numbers have shifted — run rollout history first before undoing again.
# kubectl rollout history deployment/nginx-deployment -n default
# kubectl rollout undo deployment/nginx-deployment -n default
