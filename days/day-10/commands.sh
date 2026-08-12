#!/usr/bin/env bash
# =============================================================================
# Day 10 — Kubernetes Challenge: ConfigMap + Environment Variable + Volume
# Task: namespace 'nautilus', ConfigMap 'time-config' (TIME_FREQ=10),
#       Pod 'time-check' with container 'time-check', busybox:latest,
#       env TIME_FREQ from ConfigMap, shell loop writing to log file,
#       emptyDir volume 'log-volume' mounted at /opt/sysops/time
# Platform: KodeKloud lab | kubectl on jump-host
#
# THREE RESOURCES — STRICT CREATION ORDER:
#   1. Namespace 'nautilus'      must exist before anything can be created in it
#   2. ConfigMap 'time-config'   must exist before Pod starts consuming it
#   3. Pod 'time-check'          depends on both above in the SAME namespace
#
# KEY FAILURE MODES:
#   CreateContainerConfigError — ConfigMap created in 'default' not 'nautilus'
#   CrashLoopBackOff           — shell command not wrapped in /bin/sh -c
#   Volume not found           — name mismatch between volumes[] and volumeMounts[]
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
# Deleting the namespace cascades — ConfigMap and Pod are removed with it.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get namespace nautilus &>/dev/null; then
  echo "Namespace 'nautilus' exists — deleting for a clean start"
  kubectl delete namespace nautilus
  echo "Waiting for namespace to fully terminate..."
  while kubectl get namespace nautilus &>/dev/null; do sleep 2; done
  echo "Namespace fully terminated"
else
  echo "No pre-existing 'nautilus' namespace — proceeding"
fi
echo ""

# ─── STEP 3: Create the namespace ────────────────────────────────────────────
# Namespace first — no resource can be created in it until it exists.
echo "=== Step 3: Create namespace 'nautilus' ==="
kubectl create namespace nautilus
kubectl get namespace nautilus
echo ""

# ─── STEP 4: Create the ConfigMap ────────────────────────────────────────────
# --from-literal=KEY=VALUE is the correct imperative form.
# -n nautilus is MANDATORY here. Omitting it creates the ConfigMap in 'default'.
# The Pod in 'nautilus' cannot see a ConfigMap in 'default' → CreateContainerConfigError.
echo "=== Step 4: Create ConfigMap 'time-config' in namespace nautilus ==="
kubectl create configmap time-config \
  --from-literal=TIME_FREQ=10 \
  -n nautilus

echo "ConfigMap created:"
kubectl get configmap time-config -n nautilus -o yaml
echo ""

# ─── STEP 5: Verify ConfigMap data ───────────────────────────────────────────
echo "=== Step 5: Verify ConfigMap TIME_FREQ value ==="
TIME_FREQ_VALUE=$(kubectl get configmap time-config -n nautilus \
  -o jsonpath='{.data.TIME_FREQ}')
echo "TIME_FREQ: ${TIME_FREQ_VALUE}  (expected: 10)"

if [ "${TIME_FREQ_VALUE}" == "10" ]; then
  echo "✅ ConfigMap value correct: TIME_FREQ=10"
else
  echo "❌ ConfigMap value mismatch: expected 10, got ${TIME_FREQ_VALUE}"
  exit 1
fi
echo ""

# ─── STEP 6: Write the Pod manifest ──────────────────────────────────────────
# Pod spec written directly — no dry-run patching.
# Three YAML sections to get right:
#   (a) volumes: defines log-volume as emptyDir at pod spec level
#   (b) env: injects TIME_FREQ from ConfigMap via valueFrom.configMapKeyRef
#   (c) volumeMounts: mounts log-volume at /opt/sysops/time inside the container
#
# The command wraps the shell loop in /bin/sh -c:
#   - 'while' is a shell keyword, not a binary
#   - $TIME_FREQ requires shell expansion
#   - >> requires shell I/O redirection
# Without /bin/sh -c the runtime tries exec("while") → crashes immediately.
echo "=== Step 6: Write time-check-pod.yaml ==="
cat > time-check-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: time-check
  namespace: nautilus
  labels:
    app: time-check
spec:
  volumes:
    - name: log-volume        # volume definition — referenced by volumeMounts below
      emptyDir: {}            # ephemeral: survives container restart, lost on Pod delete

  containers:
    - name: time-check
      image: busybox:latest
      command:
        - /bin/sh
        - -c
        # Shell wrapper is required — while, $TIME_FREQ, >> are all shell features
        # >> appends to log (not overwrite): accumulates history across iterations
        - "while true; do date; sleep $TIME_FREQ;done >> /opt/sysops/time/time-check.log"

      env:
        - name: TIME_FREQ                    # env variable name inside the container
          valueFrom:
            configMapKeyRef:
              name: time-config              # ConfigMap to read from (must be in same namespace)
              key: TIME_FREQ                # specific key to inject as this env variable

      volumeMounts:
        - name: log-volume                   # must match spec.volumes[].name exactly
          mountPath: /opt/sysops/time        # Kubernetes creates this directory via the mount
EOF

echo "Pod manifest written:"
cat time-check-pod.yaml
echo ""

# ─── STEP 7: Apply the Pod manifest ──────────────────────────────────────────
echo "=== Step 7: Apply time-check-pod.yaml ==="
kubectl apply -f time-check-pod.yaml
echo ""

# ─── STEP 8: Wait for Pod to be Ready ────────────────────────────────────────
# busybox:latest is a small image — pull should be fast.
# If CrashLoopBackOff: kubectl logs time-check -n nautilus → likely shell command issue.
# If CreateContainerConfigError: ConfigMap is missing or in the wrong namespace.
echo "=== Step 8: Wait for Pod Ready ==="
kubectl wait pod/time-check \
  --for=condition=Ready \
  --timeout=60s \
  -n nautilus
echo ""

# ─── STEP 9: Verify Pod status ───────────────────────────────────────────────
echo "=== Step 9: Verify Pod status ==="
kubectl get pod time-check -n nautilus
echo ""
kubectl get pod time-check -n nautilus -o wide
echo ""

# ─── STEP 10: Verify container name ──────────────────────────────────────────
echo "=== Step 10: Verify container name ==="
CONTAINER=$(kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].name}')
echo "Container name: ${CONTAINER}  (expected: time-check)"

if [ "${CONTAINER}" == "time-check" ]; then
  echo "✅ Container name correct: time-check"
else
  echo "❌ Container name mismatch: expected time-check, got ${CONTAINER}"
  exit 1
fi
echo ""

# ─── STEP 11: Verify env variable is injected from ConfigMap ─────────────────
echo "=== Step 11: Verify TIME_FREQ env variable inside container ==="
ENV_VALUE=$(kubectl exec time-check -n nautilus -c time-check \
  -- env | grep TIME_FREQ | cut -d= -f2)
echo "TIME_FREQ inside container: ${ENV_VALUE}  (expected: 10)"

if [ "${ENV_VALUE}" == "10" ]; then
  echo "✅ Environment variable TIME_FREQ correctly injected: 10"
else
  echo "❌ TIME_FREQ mismatch: expected 10, got ${ENV_VALUE}"
  exit 1
fi
echo ""

# ─── STEP 12: Verify ConfigMap reference in Pod spec ─────────────────────────
echo "=== Step 12: Verify ConfigMap reference in pod spec ==="
CM_NAME=$(kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].env[0].valueFrom.configMapKeyRef.name}')
CM_KEY=$(kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].env[0].valueFrom.configMapKeyRef.key}')
echo "ConfigMap reference: ${CM_NAME}  (expected: time-config)"
echo "ConfigMap key:       ${CM_KEY}   (expected: TIME_FREQ)"
echo ""

# ─── STEP 13: Verify volume mount ────────────────────────────────────────────
echo "=== Step 13: Verify volume mount ==="
MOUNT_NAME=$(kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].volumeMounts[0].name}')
MOUNT_PATH=$(kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].volumeMounts[0].mountPath}')
echo "Volume name:  ${MOUNT_NAME}   (expected: log-volume)"
echo "Mount path:   ${MOUNT_PATH}  (expected: /opt/sysops/time)"

if [ "${MOUNT_NAME}" == "log-volume" ] && [ "${MOUNT_PATH}" == "/opt/sysops/time" ]; then
  echo "✅ Volume mount correct"
else
  echo "❌ Volume mount mismatch"
  exit 1
fi
echo ""

# ─── STEP 14: Verify mount directory exists inside container ─────────────────
echo "=== Step 14: Verify /opt/sysops/time exists in container ==="
kubectl exec time-check -n nautilus -c time-check \
  -- ls -la /opt/sysops/time
echo ""

# ─── STEP 15: Verify log file is being written ───────────────────────────────
# TIME_FREQ=10 means at least 10 seconds between loop iterations.
# Wait 15 seconds to guarantee at least one complete iteration before reading.
echo "=== Step 15: Verify log file content (waiting 15s for first iteration) ==="
sleep 15
kubectl exec time-check -n nautilus -c time-check \
  -- cat /opt/sysops/time/time-check.log
echo ""

# ─── STEP 16: Full describe ───────────────────────────────────────────────────
echo "=== Step 16: Full describe ==="
kubectl describe pod time-check -n nautilus
echo ""

echo "============================================"
echo "All verification steps passed."
echo "Namespace nautilus:"
echo "  ConfigMap time-config:  TIME_FREQ=10"
echo "  Pod time-check:"
echo "    container:  time-check"
echo "    image:      busybox:latest"
echo "    env:        TIME_FREQ=10 (from ConfigMap)"
echo "    volume:     log-volume at /opt/sysops/time"
echo "    log file:   /opt/sysops/time/time-check.log (being written)"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Namespace deletion cascades — ConfigMap and Pod deleted with it.
# kubectl delete namespace nautilus
# rm -f time-check-pod.yaml
