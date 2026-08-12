# Day 10 — ConfigMap, Environment Variables, and Volumes

> #KodeKloud Kubernetes Challenge | Day 10 of 30

---

## 📌 The Task

| Requirement              | Value                                              |
|--------------------------|----------------------------------------------------|
| Namespace                | `nautilus`                                         |
| Pod name                 | `time-check`                                       |
| Container name           | `time-check`                                       |
| Image                    | `busybox:latest`                                   |
| ConfigMap name           | `time-config`                                      |
| ConfigMap data           | `TIME_FREQ=10`                                     |
| ConfigMap namespace      | `nautilus`                                         |
| Environment variable     | `TIME_FREQ` sourced from ConfigMap key `TIME_FREQ` |
| Command                  | `while true; do date; sleep $TIME_FREQ;done`       |
| Log file                 | `/opt/sysops/time/time-check.log`                  |
| Volume name              | `log-volume`                                       |
| Volume mount path        | `/opt/sysops/time`                                 |

---

## 🧠 Core Concepts

### What is a ConfigMap?

A **ConfigMap** is a Kubernetes object for storing non-sensitive configuration data as key-value pairs. It decouples configuration from container images — the same image runs with different settings across environments by swapping the ConfigMap, without rebuilding the image.

ConfigMaps are **namespace-scoped**. A ConfigMap in `nautilus` is only accessible to Pods running in that same namespace. This is why both the ConfigMap and Pod must exist in `nautilus`. Creating the ConfigMap in `default` and the Pod in `nautilus` produces `CreateContainerConfigError` — the Pod starts, the kubelet tries to inject the environment variable, finds no ConfigMap by that name in `nautilus`, and fails.

ConfigMap data can be consumed by a Pod in three ways:

| Method | How it works | Use case |
|--------|-------------|---------|
| `env.valueFrom.configMapKeyRef` | Injects a specific key as a named env variable | Individual keys, controlled naming |
| `envFrom.configMapRef` | Injects all keys as env variables at once | Bulk import of entire config set |
| `volumes` with `configMap` type | Mounts ConfigMap keys as files in a directory | Config files (nginx.conf, prometheus.yml) |

This task uses `valueFrom.configMapKeyRef` — injecting one specific key (`TIME_FREQ`) as an env variable of the same name. A validator checking for this structure will fail if `envFrom` is used instead, even though both inject `TIME_FREQ=10` into the container.

### Why ConfigMaps Exist — The 12-Factor App Principle

Hardcoding `sleep 10` in the container image means every configuration change requires a new image build. Putting `TIME_FREQ=10` in a ConfigMap means changing the sleep interval is a ConfigMap edit plus a Pod restart — no rebuild, no new image tag, no registry push. The same image binary runs across every environment; only the ConfigMap differs.

### Volumes and Volume Mounts — emptyDir for Ephemeral Storage

This task specifies a volume (`log-volume`) with no PersistentVolumeClaim or StorageClass — the correct type is **`emptyDir`**:

- Created fresh when the Pod is scheduled to a node
- Survives container restarts within the same Pod (if the container crashes, data is preserved)
- Destroyed when the Pod is deleted from the node — it is not durable across Pod rescheduling
- Shared across all containers in the same Pod if multiple containers mount it

Volumes are defined at the **Pod spec level** and mounted at the **container level**. The `name` field must match exactly between both locations — a mismatch fails at Pod admission:

```yaml
# Pod spec level — defines the volume
spec:
  volumes:
    - name: log-volume     ← defined here
      emptyDir: {}

# Container level — consumes the volume
  containers:
    - volumeMounts:
        - name: log-volume   ← must match exactly
          mountPath: /opt/sysops/time
```

When `log-volume` mounts at `/opt/sysops/time`, Kubernetes creates that directory path inside the container automatically. The shell redirect `>> /opt/sysops/time/time-check.log` works immediately — the parent directory exists from the mount.

### Why `/bin/sh -c` is Required for This Command

The command `while true; do date; sleep $TIME_FREQ;done` contains:
- A `while` loop — shell control flow
- `$TIME_FREQ` — shell variable expansion
- `>>` — shell I/O redirection

These are all **shell features**. The container runtime executes commands by passing them directly to the kernel's `exec` syscall — no shell is involved unless you explicitly invoke one. Without `/bin/sh -c`, the runtime looks for a binary called `while` in `PATH`. It does not exist. The container crashes immediately with:

```
Error: failed to create containerd task: failed to create shim:
exec: "while": executable file not found in $PATH
```

The fix:
```yaml
command:
  - /bin/sh
  - -c
  - "while true; do date; sleep $TIME_FREQ;done >> /opt/sysops/time/time-check.log"
```

`-c` instructs `/bin/sh` to interpret the next argument as a shell command string. Every loop iteration, shell expansion, and redirect now works correctly.

### `valueFrom.configMapKeyRef` — Injecting a Specific ConfigMap Key

```yaml
env:
  - name: TIME_FREQ                 # name of the env variable in the container
    valueFrom:
      configMapKeyRef:
        name: time-config           # ConfigMap object to read from
        key: TIME_FREQ              # key inside that ConfigMap to inject
```

Inside the container: `echo $TIME_FREQ` prints `10`. The shell command `sleep $TIME_FREQ` sleeps 10 seconds between timestamps. Changing the ConfigMap to `TIME_FREQ=30` and restarting the Pod makes it sleep 30 seconds — no image change required.

### Creation Order Is Strict

Three resources, one sequence — violating the order causes failures:

```
1. Namespace (nautilus)   → must exist before anything can be created in it
2. ConfigMap (time-config) → must exist before Pod starts consuming it
3. Pod (time-check)       → depends on both existing in the same namespace
```

---

## 🔧 Step-by-Step Solution

### Method 1 — Imperative Commands + Declarative Pod YAML (Hybrid — Exam Technique)

Namespace and ConfigMap have clean imperative shortcuts. The Pod spec is too complex for reliable dry-run patching — volume definitions, env from ConfigMap, and shell command all require YAML fields that no flag can set. Write the Pod manifest directly.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Create the namespace**
```bash
kubectl create namespace nautilus
kubectl get namespace nautilus
```

**Step 3 — Create the ConfigMap imperatively**
```bash
kubectl create configmap time-config \
  --from-literal=TIME_FREQ=10 \
  -n nautilus
```

**Step 4 — Verify the ConfigMap**
```bash
kubectl get configmap time-config -n nautilus -o yaml
kubectl get configmap time-config -n nautilus \
  -o jsonpath='{.data.TIME_FREQ}'
```
Expected: `10`

**Step 5 — Write the Pod manifest**

```yaml
# time-check-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: time-check
  namespace: nautilus
  labels:
    app: time-check
spec:
  volumes:
    - name: log-volume
      emptyDir: {}
  containers:
    - name: time-check
      image: busybox:latest
      command:
        - /bin/sh
        - -c
        - "while true; do date; sleep $TIME_FREQ;done >> /opt/sysops/time/time-check.log"
      env:
        - name: TIME_FREQ
          valueFrom:
            configMapKeyRef:
              name: time-config
              key: TIME_FREQ
      volumeMounts:
        - name: log-volume
          mountPath: /opt/sysops/time
```

**Step 6 — Apply the Pod manifest**
```bash
kubectl apply -f time-check-pod.yaml
```

**Step 7 — Wait for Pod to be Running**
```bash
kubectl wait pod/time-check \
  --for=condition=Ready \
  --timeout=60s \
  -n nautilus
```

**Step 8 — Verify the log file is being written**
```bash
sleep 12   # allow at least one full loop iteration (TIME_FREQ=10 + date execution)
kubectl exec time-check -n nautilus -c time-check \
  -- cat /opt/sysops/time/time-check.log
```

---

### Method 2 — Fully Declarative (All Resources in One Manifest)

```yaml
# nautilus-full.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: nautilus
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-config
  namespace: nautilus
data:
  TIME_FREQ: "10"
---
apiVersion: v1
kind: Pod
metadata:
  name: time-check
  namespace: nautilus
  labels:
    app: time-check
spec:
  volumes:
    - name: log-volume
      emptyDir: {}
  containers:
    - name: time-check
      image: busybox:latest
      command:
        - /bin/sh
        - -c
        - "while true; do date; sleep $TIME_FREQ;done >> /opt/sysops/time/time-check.log"
      env:
        - name: TIME_FREQ
          valueFrom:
            configMapKeyRef:
              name: time-config
              key: TIME_FREQ
      volumeMounts:
        - name: log-volume
          mountPath: /opt/sysops/time
```

```bash
kubectl apply -f nautilus-full.yaml
```

Kubernetes processes documents in order — Namespace → ConfigMap → Pod. All three are created in a single `apply`.

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Namespace
kubectl create namespace nautilus
kubectl get namespace nautilus

# ConfigMap (imperative)
kubectl create configmap time-config \
  --from-literal=TIME_FREQ=10 \
  -n nautilus
kubectl get configmap time-config -n nautilus -o yaml
kubectl get configmap time-config -n nautilus \
  -o jsonpath='{.data.TIME_FREQ}'

# Pod (declarative)
kubectl apply -f time-check-pod.yaml
kubectl wait pod/time-check --for=condition=Ready --timeout=60s -n nautilus
kubectl get pod time-check -n nautilus
kubectl get pod time-check -n nautilus -o wide

# Verify env variable injected into container
kubectl exec time-check -n nautilus -c time-check -- env | grep TIME_FREQ

# Verify volume mount path exists
kubectl exec time-check -n nautilus -c time-check -- ls /opt/sysops/time

# Read the log file (wait for at least one loop iteration first)
sleep 12
kubectl exec time-check -n nautilus -c time-check \
  -- cat /opt/sysops/time/time-check.log

# jsonpath verification
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].name}'
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].image}'
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].env[0].valueFrom.configMapKeyRef.name}'
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].env[0].valueFrom.configMapKeyRef.key}'
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].volumeMounts[0].mountPath}'
kubectl get pod time-check -n nautilus \
  -o jsonpath='{.spec.containers[0].volumeMounts[0].name}'

# Full describe
kubectl describe pod time-check -n nautilus
kubectl describe configmap time-config -n nautilus

# Cleanup (namespace deletion cascades — removes ConfigMap and Pod)
# kubectl delete namespace nautilus
```

---

## ⚠️ Common Mistakes

1. **ConfigMap created in `default` instead of `nautilus`**
   `kubectl create configmap time-config --from-literal=TIME_FREQ=10` without `-n nautilus` lands the ConfigMap in `default`. The Pod in `nautilus` looks for `time-config` in its own namespace, finds nothing, and enters `CreateContainerConfigError`. Always include `-n nautilus` on every command — ConfigMap creation included.

2. **Not wrapping the command in `/bin/sh -c`**
   `while`, `$TIME_FREQ` expansion, and `>>` are shell constructs. Without `/bin/sh -c`, the container runtime passes `while` to `exec()` as a binary name — it doesn't exist, and the container crashes immediately. The Pod shows `CrashLoopBackOff` with no stdout to inspect. Every shell construct in a container command requires the explicit shell wrapper.

3. **Volume name mismatch between `spec.volumes[]` and `volumeMounts[]`**
   `spec.volumes[].name: log-volume` and `volumeMounts[].name: log-volume` must be identical character-for-character. A typo (e.g. `log_volume` in one place) produces a Pod admission validation error: `volume "log-volume" not found`. The names are the wire connecting definition to mount — both must match.

4. **Forgetting the output redirect `>>`**
   `while true; do date; sleep $TIME_FREQ;done` without `>> /opt/sysops/time/time-check.log` runs the loop and prints timestamps to stdout (visible in `kubectl logs`), but writes nothing to the file. The task requires the file — the redirect is mandatory, not optional.

5. **Wrong log path — `/opt/data/time/` instead of `/opt/sysops/time/`**
   This task uses `/opt/sysops/time/time-check.log` and mount path `/opt/sysops/time`. A previous or similar task used `/opt/data/time/`. The validator checks the exact path. Always verify the task spec for the specific paths required — do not reuse paths from memory.

6. **Using `envFrom` instead of `env.valueFrom.configMapKeyRef`**
   `envFrom.configMapRef` imports all ConfigMap keys as environment variables. This injects `TIME_FREQ=10` into the container and the loop works correctly at runtime. However, a validator checking for the `valueFrom.configMapKeyRef` structure in the pod spec will fail. The task specifies the exact injection method — use it.

7. **Not waiting long enough before checking the log file**
   `TIME_FREQ=10` means the loop sleeps 10 seconds between iterations. Checking the log file immediately after the Pod becomes Ready may show an empty file — the first iteration hasn't completed yet. Wait at least 12–15 seconds before reading the log to confirm at least one timestamp has been written.

---

## 🌍 Real-World Context

This task combines three patterns that appear together constantly in production Kubernetes:

**ConfigMap-driven configuration** is universal. A Prometheus deployment reads its scrape config from a ConfigMap. An nginx Deployment mounts a ConfigMap as a volume containing `nginx.conf`. A Python app reads its feature flags from environment variables injected from a ConfigMap. The pattern enables environment-specific configuration without image rebuilds.

**Volume-backed log files** matter for workloads that don't log to stdout. Kubernetes' native logging (`kubectl logs`) captures only stdout/stderr. Applications that write to log files — legacy apps, apps with structured log rotation — use volumes to persist those files. In production, the volume is typically backed by shared storage (NFS, EFS, Ceph) or mounted into a sidecar log shipper that forwards to Elasticsearch or Loki.

**Shell loop containers** in busybox are a common pattern for monitoring, polling, and health-check sidecars. A sidecar that polls an endpoint every 30 seconds and writes results to a shared volume follows exactly this pattern — a `while true; do <check>; sleep $INTERVAL; done` loop with configurable interval from a ConfigMap.

In production these three patterns compose naturally:

```yaml
# production pattern — same composition as this task
containers:
  - name: log-collector
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
      - "while true; do date >> /var/log/collector/run.log; sleep $POLL_INTERVAL; done"
    env:
      - name: POLL_INTERVAL
        valueFrom:
          configMapKeyRef:
            name: collector-config
            key: POLL_INTERVAL
    volumeMounts:
      - name: log-storage
        mountPath: /var/log/collector
```

---

## ❓ Interview Q&A

**Q1: What is a ConfigMap and how does it differ from a Secret?**
A ConfigMap stores non-sensitive configuration data as key-value pairs, decoupled from the container image. A Secret stores sensitive data with base64 encoding and tighter RBAC controls; etcd can be configured to encrypt Secrets at rest. Both are namespace-scoped and consumed via environment variables or volume mounts. ConfigMaps have no special access restrictions beyond standard namespace RBAC — if you can read Pods in a namespace, you can read its ConfigMaps. Secrets have separate RBAC verbs (`get secret`) that can be denied independently.

**Q2: What are the three ways to consume a ConfigMap in a Pod?**
First, `env.valueFrom.configMapKeyRef` injects a specific key as a named environment variable — used in this task. Second, `envFrom.configMapRef` injects all ConfigMap keys as environment variables at once. Third, mounting the ConfigMap as a volume makes each key available as a file in the mount directory — the key name becomes the filename, the value becomes the file content. This third method is how config files like nginx.conf are delivered to containers without rebuilding the image.

**Q3: What is an `emptyDir` volume and when does its data get lost?**
An `emptyDir` volume is created empty when the Pod is scheduled to a node. It survives container restarts within the same Pod — if the container crashes and the kubelet restarts it, the volume data is preserved because the Pod is still running on the same node. Data is lost when the Pod is deleted, when the node fails, or when the Pod is rescheduled to a different node. For data that must survive Pod rescheduling, a PersistentVolumeClaim backed by network storage is required.

**Q4: Why does Kubernetes require `/bin/sh -c` to run shell constructs in a container?**
The `command` field in a container spec is passed directly to the container runtime, which calls `exec()` — the same system call used to run any program. `exec()` has no shell; it requires a real binary path. Shell constructs like `while`, `if`, `$VAR`, `>>` are interpreted by a shell process, not the kernel. Without invoking `/bin/sh -c`, the runtime looks for a binary named `while` — it doesn't exist, and the container exits with an exec error immediately.

**Q5: What happens if a Pod references a ConfigMap that doesn't exist in its namespace?**
The Pod enters `CreateContainerConfigError` status. The kubelet creates the Pod object but fails when it tries to inject the environment variables — the referenced ConfigMap is not found in the Pod's namespace. The Pod stays in this state until the ConfigMap is created in the correct namespace (at which point the kubelet retries) or the Pod is deleted.

**Q6: What is the difference between `>` and `>>` for shell redirects in container commands?**
`>` truncates the file on each write — each loop iteration would overwrite the log with only the latest timestamp. `>>` appends to the file — each iteration adds a new line, accumulating the log history. For a log file, `>>` is correct. Using `>` in a continuous loop effectively defeats the purpose of logging since only the most recent entry is ever visible.

**Q7: How would you update `TIME_FREQ` from 10 to 30 without rebuilding the image?**
Edit the ConfigMap: `kubectl edit configmap time-config -n nautilus` and change `TIME_FREQ` from `"10"` to `"30"`. Then restart the Pod: `kubectl delete pod time-check -n nautilus` and reapply the manifest. The new Pod picks up `TIME_FREQ=30` from the updated ConfigMap and the loop now sleeps 30 seconds. Important caveat: updating a ConfigMap does not automatically restart Pods consuming it via environment variables. The updated value is only injected into new Pods. Volume-mounted ConfigMaps propagate live updates with a propagation delay (typically 60 seconds).

---

## 📚 Resources

- [Kubernetes Docs — ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes Docs — Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Kubernetes Docs — Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Kubernetes Docs — emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)
- **Related days:** [Day 03](../day-03/README.md) — Namespaces (ConfigMaps are namespace-scoped) | [Day 01](../day-01/README.md) — Pod fundamentals extended with env vars and volumes
