# Day 11 — Troubleshooting a Multi-Container Pod

> #KodeKloud Kubernetes Challenge | Day 11 of 30

---

## 📌 The Task

| Requirement          | Value                          |
|----------------------|-------------------------------|
| Pod name             | `webserver`                   |
| Container 1 name     | `httpd-container`             |
| Container 1 image    | `httpd:latest`                |
| Container 2 name     | `sidecar-container`           |
| Container 2 image    | `ubuntu:latest`               |
| Goal                 | Pod in `Running` state, application accessible |
| Namespace            | `default`                     |

---

## 🧠 Core Concepts

### Troubleshooting Is a System, Not a Guess

Kubernetes troubleshooting has a deterministic order of operations. Engineers who jump straight to "delete and recreate" without reading the error waste time and miss the lesson. The correct sequence every time:

```
1. kubectl get pod          → What state is the pod in?
2. kubectl describe pod     → What events explain that state?
3. kubectl logs             → What did the container actually output?
4. Fix the root cause       → Export YAML, edit, delete, reapply
5. Verify                   → Pod Running + app accessible
```

Never skip step 2. The `Events` section of `kubectl describe` is the most information-dense output in Kubernetes debugging. It tells you exactly what the kubelet and scheduler attempted and where they failed.

### Pod States and What They Mean

Before fixing anything, understand what the current state is telling you:

| Status | Meaning | Where to look |
|--------|---------|--------------|
| `Pending` | Pod scheduled but containers not started | `describe` → Events: scheduling/image pull |
| `ImagePullBackOff` | Container image cannot be pulled | `describe` → wrong image name, tag, registry auth |
| `ErrImagePull` | First pull attempt failed | Same as above — transient or permanent |
| `CrashLoopBackOff` | Container starts but exits non-zero, kubelet keeps retrying | `logs` → what the process outputted before dying |
| `OOMKilled` | Container exceeded memory limit | `describe` → Last State reason |
| `CreateContainerConfigError` | ConfigMap or Secret referenced but missing | `describe` → missing resource |
| `Running` | Container is up — but app may still be broken | `logs`, `exec`, `curl` to verify |

### The Sidecar Pattern — and Why ubuntu Exits Immediately

A **sidecar container** runs alongside the main container in the same Pod, sharing the same network namespace and volumes. Common sidecar roles: log shippers, monitoring agents, proxies (Envoy), cert refreshers.

The critical behaviour of `ubuntu:latest`: its default entrypoint is `/bin/bash`. When bash has no terminal and no commands piped to it, it exits immediately with code 0 — a successful exit. Kubernetes sees the container exit and, depending on the `restartPolicy`, either restarts it (creating `CrashLoopBackOff`) or marks it `Completed`.

**A sidecar that exits immediately defeats its purpose.** It must run a foreground process that does not exit:

```yaml
# Wrong — ubuntu exits immediately, enters CrashLoopBackOff
- name: sidecar-container
  image: ubuntu:latest

# Correct — sleep infinity keeps the container alive
- name: sidecar-container
  image: ubuntu:latest
  command: ["/bin/bash", "-c", "sleep infinity"]
```

This is the most common cause of CrashLoopBackOff for `ubuntu:latest` and `busybox:latest` sidecars.

### Pod Spec Immutability — Why You Can't Just Edit

Most fields in a running Pod's spec are **immutable**. `kubectl edit pod webserver` allows you to change a very limited subset of fields (annotations, some labels, resource limits/requests in some configurations). You cannot change the container image, command, or volume mounts on a running Pod.

The universal fix workflow for a broken Pod:

```bash
# 1. Export the current spec (broken)
kubectl get pod webserver -o yaml > webserver-fix.yaml

# 2. Edit the file to fix the issue

# 3. Delete the broken pod
kubectl delete pod webserver

# 4. Apply the fixed spec
kubectl apply -f webserver-fix.yaml
```

### Multi-Container Pod Logs — Each Container Has Its Own Log Stream

In a multi-container Pod, every container has independent stdout/stderr captured by the kubelet. `kubectl logs` requires `-c <container-name>` to specify which container's logs to read:

```bash
kubectl logs webserver -c httpd-container       # main container logs
kubectl logs webserver -c sidecar-container     # sidecar logs
kubectl logs webserver -c sidecar-container --previous  # logs from previous (crashed) run
```

`--previous` is critical for CrashLoopBackOff debugging: the container keeps restarting, so its current log may be empty. `--previous` shows logs from the last completed (failed) run.

---

## 🔧 Step-by-Step Solution

### Phase 1 — Investigate (Run These First, Fix Nothing Yet)

**Step 1 — Verify cluster access and check pod state**
```bash
kubectl get nodes
kubectl get pod webserver -n default
kubectl get pod webserver -n default -o wide
```

Note the exact STATUS. CrashLoopBackOff and ImagePullBackOff require different fixes.

**Step 2 — Read the Events section of describe**

This is the most important command in this task:
```bash
kubectl describe pod webserver -n default
```

Look specifically at:
- `State:` and `Last State:` for each container — reason for failure
- `Events:` at the bottom — chronological record of what Kubernetes attempted
- `Image:` fields — confirm images match `httpd:latest` and `ubuntu:latest`

**Step 3 — Read container logs**
```bash
# httpd-container logs
kubectl logs webserver -n default -c httpd-container

# sidecar-container logs (current run)
kubectl logs webserver -n default -c sidecar-container

# sidecar-container logs from previous (crashed) run
kubectl logs webserver -n default -c sidecar-container --previous
```

**Step 4 — Export the current broken Pod spec**
```bash
kubectl get pod webserver -n default -o yaml > webserver-fix.yaml
```

This is the source file you will edit and reapply.

---

### Phase 2 — Fix (Based on What You Found)

**Most likely root cause: `sidecar-container` exits immediately**

`ubuntu:latest` has no foreground process by default. Without a command, the container starts, bash finds nothing to do, exits 0. With `restartPolicy: Always` (Deployment default) or `OnFailure`, the kubelet restarts it — creating CrashLoopBackOff.

**Step 5 — Edit the exported YAML**

Open `webserver-fix.yaml` and locate the `sidecar-container` spec. Add a `command` that runs a foreground process:

```yaml
# Find this in webserver-fix.yaml:
- name: sidecar-container
  image: ubuntu:latest
  # Add these lines:
  command:
    - /bin/bash
    - -c
    - "sleep infinity"
```

Or use sed to patch it directly:
```bash
sed -i '/name: sidecar-container/{n; /image: ubuntu:latest/a\  command: ["/bin/bash", "-c", "sleep infinity"]
}' webserver-fix.yaml
```

**Step 6 — Remove server-generated fields before reapplying**

`kubectl get pod -o yaml` includes fields that the API server adds (resourceVersion, uid, creationTimestamp, status block). These cause errors on `kubectl apply`. Clean them:

```bash
# Remove the status block and server-generated metadata
kubectl get pod webserver -n default -o yaml | \
  grep -v '^\s*resourceVersion\|^\s*uid:\|^\s*creationTimestamp:\|^status:' \
  > webserver-fix.yaml
```

Or edit manually — delete the `status:` section and the top-level `creationTimestamp`, `resourceVersion`, `uid`, and `selfLink` fields under `metadata`.

**Step 7 — Delete the broken Pod**
```bash
kubectl delete pod webserver -n default
```

Wait for it to fully terminate:
```bash
kubectl wait pod/webserver --for=delete --timeout=30s -n default 2>/dev/null || true
```

**Step 8 — Apply the fixed spec**
```bash
kubectl apply -f webserver-fix.yaml
```

**Step 9 — Wait for Running state**
```bash
kubectl wait pod/webserver --for=condition=Ready --timeout=60s -n default
```

---

### Phase 3 — Verify (Confirm Both Containers Are Healthy)

**Step 10 — Confirm Pod is Running with both containers Ready**
```bash
kubectl get pod webserver -n default
```
Expected: `READY 2/2` — both containers running.

**Step 11 — Verify each container individually**
```bash
kubectl describe pod webserver -n default | grep -A5 "Container ID"
kubectl logs webserver -n default -c httpd-container
kubectl logs webserver -n default -c sidecar-container
```

**Step 12 — Verify the application is accessible**
```bash
# Get the Pod IP
POD_IP=$(kubectl get pod webserver -n default -o jsonpath='{.status.podIP}')
echo "Pod IP: ${POD_IP}"

# Test from within the cluster (from another pod or via exec)
kubectl exec webserver -n default -c sidecar-container \
  -- curl -s http://localhost:80
# Or test from the sidecar (same network namespace as httpd-container)
```

---

## 💻 Commands Reference

```bash
# ── Investigation ──────────────────────────────────────────────────────────
kubectl get pod webserver -n default
kubectl get pod webserver -n default -o wide
kubectl describe pod webserver -n default
kubectl logs webserver -n default -c httpd-container
kubectl logs webserver -n default -c sidecar-container
kubectl logs webserver -n default -c sidecar-container --previous

# ── Export and fix ─────────────────────────────────────────────────────────
kubectl get pod webserver -n default -o yaml > webserver-fix.yaml
# Edit webserver-fix.yaml — add command to sidecar-container
kubectl delete pod webserver -n default
kubectl apply -f webserver-fix.yaml

# ── Verify ─────────────────────────────────────────────────────────────────
kubectl get pod webserver -n default
kubectl wait pod/webserver --for=condition=Ready --timeout=60s -n default
kubectl describe pod webserver -n default

# Test application from within cluster
kubectl exec webserver -n default -c sidecar-container -- curl -s http://localhost

# Get pod IP
kubectl get pod webserver -n default -o jsonpath='{.status.podIP}'

# Check READY count (must be 2/2)
kubectl get pod webserver -n default --no-headers | awk '{print $2}'

# All events in namespace (broader view)
kubectl get events -n default --sort-by='.lastTimestamp'

# ── Useful debugging commands ───────────────────────────────────────────────
# Enter the sidecar to debug from inside the pod
kubectl exec -it webserver -n default -c sidecar-container -- /bin/bash

# Check what process is running inside the sidecar
kubectl exec webserver -n default -c sidecar-container -- ps aux
```

---

## ⚠️ Common Mistakes

1. **⚠️ CONFIRMED IN LAB: Image tag typo — `httpd:latests` instead of `httpd:latest`**
   The actual root cause in this task was one extra character. The `httpd-container` spec had `httpd:latests` — Docker Hub returned `not found` because that tag does not exist. The sidecar started perfectly; only `httpd-container` was broken. The Events section made it unambiguous:
   ```
   Failed to pull image "httpd:latests": ... httpd:latests: not found
   ```
   **Fix Option A — Fastest** (image patch directly on the failing pod — works because the container is not yet running):
   ```bash
   kubectl set image pod/webserver httpd-container=httpd:latest -n default
   kubectl get pod webserver -n default -w   # watch it recover
   ```
   **Fix Option B — Universal** (export → fix → delete → reapply):
   ```bash
   kubectl get pod webserver -n default -o yaml > webserver-fix.yaml
   sed -i 's/httpd:latests/httpd:latest/g' webserver-fix.yaml
   kubectl delete pod webserver -n default
   kubectl apply -f webserver-fix.yaml
   ```
   The lesson: `ImagePullBackOff` and `CrashLoopBackOff` look identical in `kubectl get pods` STATUS output but need completely different fixes. Read Events before touching anything.

2. **Deleting and recreating without reading the error first**
   Deleting a failing Pod and reapplying the same spec recreates the same problem. Always run `kubectl describe pod` and `kubectl logs --previous` first. The Events section tells you the exact failure reason — CrashLoopBackOff, ImagePullBackOff, OOMKilled — each with a different fix. Guessing wastes the lab time limit.

2. **Not using `--previous` flag when a container is in CrashLoopBackOff**
   In CrashLoopBackOff, the container has already exited before you run `kubectl logs`. The current container may have just started and its logs are empty. `kubectl logs -c sidecar-container --previous` fetches the logs from the last completed (failed) run — the one that actually contains the error.

3. **Applying a `kubectl get -o yaml` export directly without cleaning server fields**
   `kubectl get pod -o yaml` includes `resourceVersion`, `uid`, `status:` block, and other server-managed fields. Applying this directly causes a conflict error. Remove the `status:` section entirely and the auto-generated metadata fields before reapplying. Alternatively, use `kubectl apply -f` with `--force` on a clean file.

4. **Forgetting that containers in the same Pod share the same network namespace**
   The `sidecar-container` and `httpd-container` share `localhost`. Testing the httpd application from within the sidecar using `curl http://localhost:80` works because both containers share the Pod's network stack. This also means port conflicts — if both containers try to bind the same port, one will fail.

5. **Checking `STATUS=Running` but not `READY` count**
   A Pod can show `STATUS=Running` while `READY=1/2` — one container is running, one is not ready (or restarting). The application may appear to work while the sidecar is still CrashLoopBackOffing. Always verify `READY=2/2` for a two-container Pod.

6. **Not confirming the images match the task spec after fixing**
   After fixing the sidecar command issue, confirm the images are still `httpd:latest` and `ubuntu:latest`. Edits to YAML files sometimes accidentally alter adjacent lines. Verify with:
   ```bash
   kubectl get pod webserver -o jsonpath='{range .spec.containers[*]}{.name}: {.image}{"\n"}{end}'
   ```

7. **Trying to `kubectl edit` immutable pod spec fields**
   `kubectl edit pod webserver` allows editing some fields but not container images or commands. Attempting to change the `command` field via `kubectl edit` returns a validation error. The only path for spec changes on a running Pod is delete + reapply. Know which fields are mutable (labels, annotations, resource limits) and which are not (container name, image, command, volumes).

---

## 🌍 Real-World Context

Multi-container Pod troubleshooting is a daily reality in production Kubernetes operations. The sidecar pattern is ubiquitous:

- **Istio/Envoy proxy sidecars** — every Pod in an Istio mesh has an `istio-proxy` sidecar injected automatically
- **Log shipping sidecars** — Fluentd or Promtail runs as a sidecar reading log files from a shared volume
- **Cert-manager sidecars** — refresh TLS certificates and write them to a shared volume
- **Monitoring agents** — Datadog, New Relic, or Dynatrace agents run as sidecars

When a sidecar CrashLoopBackOff hits production, it does not necessarily take the main container down — the main container (`httpd-container`) continues running. But the sidecar's function (log shipping, traffic proxying, metrics collection) silently fails. Logs stop flowing, metrics go dark, traffic may not be proxied correctly. This is why CrashLoopBackOff on a sidecar is a critical alert even when the main application appears healthy.

The `--previous` log technique is used in production incident postmortems: after a container has been automatically restarted, the current logs show a fresh start. The crash evidence is in the previous run's logs — the only way to access it without centralised log storage.

---

## ❓ Interview Q&A

**Q1: A pod shows STATUS=Running but the application isn't responding. How do you debug it?**
First check READY count — a Running pod with 0/2 ready has containers that haven't passed readiness probes. Then `kubectl describe pod` for Events and container state. `kubectl logs -c <container>` for application errors. `kubectl exec` into the container to test connectivity directly. Finally check if the Service selector matches the Pod's labels — the app may be healthy but unreachable because the Service targets the wrong Pods.

**Q2: What is CrashLoopBackOff and what does the "backoff" part mean?**
CrashLoopBackOff means the container starts, exits with a non-zero code, and the kubelet restarts it. The "backoff" is exponential — the kubelet waits 10s, 20s, 40s, 80s, 160s, then caps at 5 minutes between restart attempts. This prevents a broken container from hammering the node with rapid restart cycles. The backoff resets if the container runs successfully for 10 minutes.

**Q3: How do you view logs from a container that has already crashed?**
`kubectl logs <pod> -c <container> --previous`. The `--previous` flag fetches logs from the last terminated container instance rather than the currently running (or just-started) one. Without it, you see an empty log for a container that has just been restarted — the crash evidence was in the previous run.

**Q4: Why can't you change a container's command with `kubectl edit pod`?**
Container spec fields — image, name, command, args, ports, volume mounts — are immutable after Pod creation. This is a design decision: Pods are treated as cattle, not pets. If the spec needs to change, you delete and recreate. Higher-level controllers like Deployments manage this transparently with rolling updates. For a bare Pod (like in this task), the workflow is: export YAML → edit → delete old pod → apply fixed YAML.

**Q5: Two containers in the same Pod — how do they communicate?**
They share the same network namespace, meaning they share a single IP address and can communicate over `localhost`. If `httpd-container` listens on port 80, `sidecar-container` can reach it at `http://localhost:80` — no Service required. They also share any volumes mounted in both containers, which is the mechanism for log files to be written by one container and read by another.

**Q6: What is the sidecar pattern and when would you use it?**
A sidecar is a helper container that runs alongside the main container in the same Pod, extending its functionality without modifying the main container's image. Common uses: Envoy proxy for service mesh traffic management, Fluentd for log collection from a shared volume, Vault agent for secret injection, cert-refresh containers. The sidecar shares the Pod's network and volumes but has its own process and filesystem.

**Q7: How do you verify that all containers in a multi-container Pod are running correctly?**
Check `READY` count matches total containers: `kubectl get pod webserver` should show `2/2`. Then verify each container individually: `kubectl describe pod webserver` shows each container's State and Last State. `kubectl logs webserver -c <each-container>` confirms expected output. For functional testing, `kubectl exec -c sidecar-container -- curl http://localhost` tests cross-container connectivity. `kubectl exec -c httpd-container -- ps aux` confirms the httpd process is running inside its container.

---

## 📚 Resources

- [Kubernetes Docs — Debugging Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Kubernetes Docs — Multi-container Pods](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers)
- [Kubernetes Docs — Sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Kubernetes Docs — kubectl logs](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#logs)
- **Related days:** [Day 01](../day-01/README.md) — Pod fundamentals | [Day 04](../day-04/README.md) — Resource limits (OOMKill is another crash cause) | [Day 10](../day-10/README.md) — Volumes shared between containers
