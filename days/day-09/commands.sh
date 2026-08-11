#!/usr/bin/env bash
# =============================================================================
# Day 09 — Kubernetes Challenge: Create a Job
# Task: Job 'countdown-datacenter', image debian:latest,
#       container 'container-countdown-datacenter', command 'sleep 5',
#       restartPolicy Never, spec.template.metadata.name 'countdown-datacenter'
# Platform: KodeKloud lab | kubectl on jump-host
#
# TWO PATCHES REQUIRED (more than any previous day):
#
#   PATCH 1 — spec.template.metadata.name
#     kubectl create job generates template metadata WITHOUT a name field.
#     The task explicitly requires name: countdown-datacenter in the template
#     metadata. This field must be inserted via sed after generation.
#     Target: the 6-space-indented 'creationTimestamp: null' line (template
#     metadata), NOT the 2-space-indented one (Job's own metadata).
#
#   PATCH 2 — container name
#     kubectl create job names the container 'countdown-datacenter' (Job name).
#     Task requires 'container-countdown-datacenter'.
#     Same range-restricted sed pattern from Day 08/09.
#     Patch 1 must run first — the template name added by Patch 1 is OUTSIDE
#     the '- command:/,/restartPolicy:/' range, so Patch 2 won't touch it.
#
# WHY Method 2 (direct YAML) is recommended for this task:
#   Two sequential sed patches on a deeply nested CronJob/Job YAML is
#   error-prone under time pressure. Writing the manifest directly is
#   faster once you know the Job spec structure.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
# Job deletion cascades to its Pods.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get job countdown-datacenter -n default &>/dev/null; then
  echo "Found existing Job 'countdown-datacenter' — deleting before recreating"
  kubectl delete job countdown-datacenter -n default
  echo "Waiting for Job Pods to terminate..."
  sleep 3
else
  echo "No pre-existing Job found — proceeding"
fi
echo ""

# ─── STEP 3: Write the Job manifest directly ─────────────────────────────────
# Method 2 (direct YAML) is recommended for this task over Method 1
# (dry-run + two patches) because the patches are finicky and the manifest
# structure is small enough to write from memory.
# apiVersion: batch/v1 — same as CronJob, NOT apps/v1 or v1.
echo "=== Step 3: Write countdown-job.yaml ==="
cat > countdown-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-datacenter
  namespace: default
spec:
  backoffLimit: 6                     # retry up to 6 times before marking Job Failed
  template:
    metadata:
      name: countdown-datacenter      # required by task — name on the pod template
    spec:
      restartPolicy: Never            # new Pod created on failure (not in-place restart)
      containers:
        - name: container-countdown-datacenter
          image: debian:latest
          command:
            - sleep
            - "5"                     # exits 0 after 5 seconds — Job completes
EOF

echo "Manifest written:"
cat countdown-job.yaml
echo ""

# ─── METHOD 1 ALTERNATIVE (dry-run + patch) ────────────────────────────────
# Uncomment this block if using the imperative dry-run approach instead.
# Requires two sed patches in sequence.
#
# kubectl create job countdown-datacenter \
#   --image=debian:latest \
#   --dry-run=client -o yaml \
#   -- sleep 5 > countdown-job.yaml
#
# # Patch 1: insert template name after 6-space creationTimestamp (template.metadata)
# # The 2-space creationTimestamp (job metadata) is NOT matched by this pattern.
# sed -i 's/^      creationTimestamp: null$/      creationTimestamp: null\n      name: countdown-datacenter/' countdown-job.yaml
#
# # Patch 2: fix container name (range-restricted — safe after Patch 1)
# sed -i '/- command:/,/restartPolicy:/ s/name: countdown-datacenter/name: container-countdown-datacenter/' countdown-job.yaml
# ─────────────────────────────────────────────────────────────────────────────

# ─── STEP 4: Apply the manifest ──────────────────────────────────────────────
echo "=== Step 4: Apply countdown-job.yaml ==="
kubectl apply -f countdown-job.yaml
echo ""

# ─── STEP 5: Wait for Job to complete ────────────────────────────────────────
# 'sleep 5' exits 0 after 5 seconds — Job should complete within 30 seconds.
# If this times out: check kubectl get pods for ImagePullBackOff (debian:latest pull).
echo "=== Step 5: Wait for Job to complete ==="
kubectl wait job/countdown-datacenter \
  --for=condition=Complete \
  --timeout=60s \
  -n default
echo ""

# ─── STEP 6: Verify Job status ───────────────────────────────────────────────
# COMPLETIONS=1/1 confirms the Job succeeded.
# DURATION shows how long the Job ran.
echo "=== Step 6: Verify Job status ==="
kubectl get job countdown-datacenter -n default
echo ""

# ─── STEP 7: Verify spec.template.metadata.name ──────────────────────────────
# This is the field the task requires that kubectl create job doesn't generate.
# The jsonpath digs into spec.template.metadata.name specifically.
echo "=== Step 7: Verify spec.template.metadata.name ==="
TEMPLATE_NAME=$(kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.metadata.name}')
echo "Template metadata name: ${TEMPLATE_NAME}  (expected: countdown-datacenter)"

if [ "${TEMPLATE_NAME}" == "countdown-datacenter" ]; then
  echo "✅ Template metadata name correct: countdown-datacenter"
else
  echo "❌ Template metadata name mismatch: expected countdown-datacenter, got ${TEMPLATE_NAME}"
  exit 1
fi
echo ""

# ─── STEP 8: Verify container name ───────────────────────────────────────────
echo "=== Step 8: Verify container name ==="
CONTAINER=$(kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER}  (expected: container-countdown-datacenter)"

if [ "${CONTAINER}" == "container-countdown-datacenter" ]; then
  echo "✅ Container name correct: container-countdown-datacenter"
else
  echo "❌ Container name mismatch: expected container-countdown-datacenter, got ${CONTAINER}"
  exit 1
fi
echo ""

# ─── STEP 9: Verify image ────────────────────────────────────────────────────
echo "=== Step 9: Verify image ==="
IMAGE=$(kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: ${IMAGE}  (expected: debian:latest)"

if [ "${IMAGE}" == "debian:latest" ]; then
  echo "✅ Image correct: debian:latest"
else
  echo "❌ Image mismatch: expected debian:latest, got ${IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 10: Verify restart policy ──────────────────────────────────────────
echo "=== Step 10: Verify restartPolicy ==="
RESTART=$(kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.restartPolicy}')
echo "restartPolicy: ${RESTART}  (expected: Never)"

if [ "${RESTART}" == "Never" ]; then
  echo "✅ restartPolicy correct: Never"
else
  echo "❌ restartPolicy mismatch: expected Never, got ${RESTART}"
  exit 1
fi
echo ""

# ─── STEP 11: Verify the Pod completed successfully ──────────────────────────
# Pod STATUS=Completed (not Running) is the correct state after sleep 5 exits 0.
echo "=== Step 11: Verify Pod completed ==="
kubectl get pods -n default -l job-name=countdown-datacenter
echo ""

# ─── STEP 12: Read Pod logs ───────────────────────────────────────────────────
# sleep 5 produces no stdout output — empty log is expected and correct.
# Verifying the Pod ran and the container name is accessible via -c flag.
echo "=== Step 12: Pod logs (sleep 5 has no stdout — empty is correct) ==="
POD=$(kubectl get pods -n default \
  -l job-name=countdown-datacenter \
  -o jsonpath='{.items[0].metadata.name}')
echo "Pod name: ${POD}"
kubectl logs "${POD}" -n default -c container-countdown-datacenter \
  && echo "(no output — sleep 5 produces none)" || true
echo ""

# ─── STEP 13: Full describe ───────────────────────────────────────────────────
# Look for: Completions, Start Time, Completion Time, Pod Statuses, Labels.
echo "=== Step 13: Full describe ==="
kubectl describe job countdown-datacenter -n default
echo ""

echo "============================================"
echo "All verification steps passed."
echo "Job countdown-datacenter:"
echo "  status:              Complete (1/1)"
echo "  template name:       countdown-datacenter"
echo "  container name:      container-countdown-datacenter"
echo "  image:               debian:latest"
echo "  restartPolicy:       Never"
echo "  command:             sleep 5"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting the Job cascades — its Pods are garbage-collected.
# kubectl delete job countdown-datacenter -n default
# rm -f countdown-job.yaml
