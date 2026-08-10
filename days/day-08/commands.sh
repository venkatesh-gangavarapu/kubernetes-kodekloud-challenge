#!/usr/bin/env bash
# =============================================================================
# Day 08 — Kubernetes Challenge: Create a CronJob
# Task: CronJob 'datacenter', schedule */6 * * * *, image httpd:latest,
#       container cron-datacenter, command 'echo Welcome to xfusioncorp!',
#       restartPolicy OnFailure
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY LESSONS COMPOUNDING FROM PREVIOUS DAYS:
#   1. kubectl create cronjob names the container after the CronJob ('datacenter').
#      Same dry-run + sed patch pattern as Day 01/04/08.
#      BUT the CronJob YAML is deeply nested — multiple 'name: datacenter'
#      entries exist at different indentation levels:
#        2-space:  metadata.name (CronJob name — leave it)
#        6-space:  jobTemplate.metadata (leave it)
#        deep:     containers[].name (patch this to cron-datacenter)
#      Use a range-restricted sed to target ONLY the container entry.
#
#   2. restartPolicy must be OnFailure or Never — NOT Always.
#      Always is only valid for long-running services (Deployments).
#      The API server rejects Always for Job/CronJob at admission.
#
#   3. apiVersion is batch/v1 — not apps/v1, not v1.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
# Deleting the CronJob leaves any already-created Jobs and Pods in place.
# Delete those separately if needed.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get cronjob datacenter -n default &>/dev/null; then
  echo "Found existing CronJob 'datacenter' — deleting before recreating"
  kubectl delete cronjob datacenter -n default
else
  echo "No pre-existing CronJob 'datacenter' found — proceeding"
fi
echo ""

# ─── STEP 3: Generate CronJob manifest via dry-run ───────────────────────────
# kubectl create cronjob exists and supports --schedule, --image, --restart,
# and a command after '--'. It correctly populates the deep spec structure
# including jobTemplate.spec.template — faster than writing from scratch.
# The only flaw: container is named 'datacenter', not 'cron-datacenter'.
echo "=== Step 3: Generate datacenter-cronjob.yaml via dry-run ==="
kubectl create cronjob datacenter \
  --image=httpd:latest \
  --schedule="*/6 * * * *" \
  --restart=OnFailure \
  --dry-run=client -o yaml \
  -- echo "Welcome to xfusioncorp!" > datacenter-cronjob.yaml

echo "Generated manifest (before patch):"
cat datacenter-cronjob.yaml
echo ""

# ─── STEP 4: Patch the container name ────────────────────────────────────────
# The generated YAML has 'name: datacenter' in multiple locations.
# Standard sed 's/name: datacenter/...' would rename ALL of them — including
# metadata.name (the CronJob name) which must remain 'datacenter'.
#
# The range restriction '/- command:/,/restartPolicy:/' limits the substitution
# to the block between '- command:' and 'restartPolicy:' — exactly where the
# container entry lives in the deeply nested CronJob spec.
echo "=== Step 4: Patch container name to cron-datacenter ==="
sed -i '/- command:/,/restartPolicy:/ s/name: datacenter/name: cron-datacenter/' datacenter-cronjob.yaml

echo "Patched manifest:"
cat datacenter-cronjob.yaml
echo ""

# Verify the patch — cron-datacenter should appear once, datacenter should still
# appear in metadata.name
echo "Verifying patch (cron-datacenter should appear once):"
grep "name:" datacenter-cronjob.yaml
echo ""

# ─── STEP 5: Apply the manifest ──────────────────────────────────────────────
echo "=== Step 5: Apply datacenter-cronjob.yaml ==="
kubectl apply -f datacenter-cronjob.yaml
echo ""

# ─── STEP 6: Verify CronJob was created ──────────────────────────────────────
# LAST SCHEDULE shows <none> until the first trigger fires (up to 6 minutes).
# ACTIVE shows how many Jobs are currently running.
# SUSPEND=False confirms the CronJob is active (not paused).
echo "=== Step 6: Verify CronJob status ==="
kubectl get cronjob datacenter -n default
echo ""

# ─── STEP 7: Verify schedule ─────────────────────────────────────────────────
echo "=== Step 7: Verify schedule ==="
SCHEDULE=$(kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.schedule}')
echo "Schedule: ${SCHEDULE}  (expected: */6 * * * *)"

if [ "${SCHEDULE}" == "*/6 * * * *" ]; then
  echo "✅ Schedule correct: */6 * * * *"
else
  echo "❌ Schedule mismatch: expected */6 * * * *, got ${SCHEDULE}"
  exit 1
fi
echo ""

# ─── STEP 8: Verify restartPolicy ────────────────────────────────────────────
# The restartPolicy lives deep inside the spec:
# .spec.jobTemplate.spec.template.spec.restartPolicy
echo "=== Step 8: Verify restartPolicy ==="
RESTART=$(kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}')
echo "restartPolicy: ${RESTART}  (expected: OnFailure)"

if [ "${RESTART}" == "OnFailure" ]; then
  echo "✅ restartPolicy correct: OnFailure"
else
  echo "❌ restartPolicy mismatch: expected OnFailure, got ${RESTART}"
  exit 1
fi
echo ""

# ─── STEP 9: Verify container name ───────────────────────────────────────────
echo "=== Step 9: Verify container name ==="
CONTAINER=$(kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER}  (expected: cron-datacenter)"

if [ "${CONTAINER}" == "cron-datacenter" ]; then
  echo "✅ Container name correct: cron-datacenter"
else
  echo "❌ Container name mismatch: expected cron-datacenter, got ${CONTAINER}"
  exit 1
fi
echo ""

# ─── STEP 10: Verify image ────────────────────────────────────────────────────
echo "=== Step 10: Verify image ==="
IMAGE=$(kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
echo "Image: ${IMAGE}  (expected: httpd:latest)"

if [ "${IMAGE}" == "httpd:latest" ]; then
  echo "✅ Image correct: httpd:latest"
else
  echo "❌ Image mismatch: expected httpd:latest, got ${IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 11: Verify command ──────────────────────────────────────────────────
echo "=== Step 11: Verify command ==="
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].command}'
echo ""

# ─── STEP 12: Manually trigger a Job for immediate testing ───────────────────
# The CronJob won't fire for up to 6 minutes. Manually create a Job from
# the CronJob template to verify execution now — without waiting.
echo "=== Step 12: Trigger a manual Job run for testing ==="
kubectl create job datacenter-manual-test \
  --from=cronjob/datacenter \
  -n default
echo ""

# ─── STEP 13: Wait for the manual Job to complete ────────────────────────────
echo "=== Step 13: Wait for manual Job to complete ==="
kubectl wait job/datacenter-manual-test \
  --for=condition=Complete \
  --timeout=60s \
  -n default
echo ""

# ─── STEP 14: Verify the Pod completed and check logs ────────────────────────
# The Pod from a completed Job shows STATUS=Completed (not Running).
echo "=== Step 14: Check Job Pod status and logs ==="
kubectl get pods -n default -l job-name=datacenter-manual-test
echo ""

POD=$(kubectl get pods -n default \
  -l job-name=datacenter-manual-test \
  -o jsonpath='{.items[0].metadata.name}')
echo "Pod: ${POD}"
echo "Logs:"
kubectl logs "${POD}" -n default -c cron-datacenter
echo ""

# ─── STEP 15: Full describe ───────────────────────────────────────────────────
echo "=== Step 15: Full describe ==="
kubectl describe cronjob datacenter -n default
echo ""

echo "============================================"
echo "All verification steps passed."
echo "CronJob datacenter:"
echo "  schedule:        */6 * * * *"
echo "  restartPolicy:   OnFailure"
echo "  container name:  cron-datacenter"
echo "  image:           httpd:latest"
echo "  command output:  Welcome to xfusioncorp!"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting the CronJob does NOT delete already-created Jobs or their Pods.
# Delete those separately.
# kubectl delete cronjob datacenter -n default
# kubectl delete job datacenter-manual-test -n default
# rm -f datacenter-cronjob.yaml
