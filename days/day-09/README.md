# Day 09 — Creating a Kubernetes Job

> #KodeKloud Kubernetes Challenge | Day 8 of 30

---

## 📌 The Task

| Requirement                | Value                            |
|----------------------------|----------------------------------|
| Kind                       | Job                              |
| Job name                   | `countdown-datacenter`           |
| Template metadata name     | `countdown-datacenter`           |
| Container name             | `container-countdown-datacenter` |
| Image                      | `debian:latest`                  |
| Command                    | `sleep 5`                        |
| Restart policy             | `Never`                          |
| Namespace                  | `default`                        |

---

## 🧠 Core Concepts

### Job vs CronJob — The Relationship Established in Day 08

Day 08 covered CronJobs. The hierarchy was: CronJob → Job → Pod. Today we work one level down — creating the **Job** directly, without a CronJob scheduling it.

A Job is a **one-time, run-to-completion** workload controller. Unlike a Deployment (which keeps Pods running indefinitely), a Job creates Pods, tracks their successful completions, and stops. Once the required number of Pods complete successfully, the Job is marked `Complete` and no more Pods are created.

```
Job (countdown-datacenter)
  └── Pod (countdown-datacenter-<hash>)   ← runs sleep 5, exits 0, Job completes
```

When does this two-layer chain become three? Only when the Job is wrapped by a CronJob — which fires repeatedly on a schedule and creates a new Job each time.

### `spec.template.metadata.name` — What It Actually Does

This task requires `spec.template.metadata.name: countdown-datacenter`. This is a field that most engineers overlook because `kubectl create job` does not populate it by default. It is worth understanding what it does.

In Kubernetes, Pods created by a Job have their names auto-generated from the Job name plus a random suffix (`countdown-datacenter-x4bpt`). The `spec.template.metadata.name` field sets a **name on the Pod template** — it becomes part of the generated Pod name. Unlike Deployment or ReplicaSet pod templates where this field is rarely set, Jobs and CronJobs sometimes carry it to give the pods a more identifiable name prefix in logs and `kubectl get pods` output.

The field does not override the random suffix — it provides additional naming context in the template itself. The task validator checks this field exists on the template metadata, not just on the Job's own `metadata.name`.

### `restartPolicy: Never` vs `OnFailure` — Two Different Failure Models

Both are valid for Jobs, but they produce completely different behaviour on Pod failure:

**`restartPolicy: OnFailure`**
- The container is restarted **inside the same Pod** when it exits non-zero
- The Pod name stays the same; the container restart counter increments
- Retries happen on the same node, with the same Pod spec
- Good for: commands with transient failures where retry-in-place makes sense

**`restartPolicy: Never`**
- When the container exits non-zero, the Pod is **not restarted** — it moves to `Failed` status
- The Job controller creates a **brand new Pod** for the retry
- Each retry gets a fresh Pod (new name, potentially new node)
- Good for: tasks where a fresh environment is important for each attempt, or where you want failed Pods preserved for inspection

`restartPolicy: Never` is the recommended policy for Jobs in most production scenarios because it gives you a record of each failed attempt as a separate Pod, with its own logs, for debugging. With `OnFailure`, the container restart overwrites the logs from the previous attempt.

For this task: `sleep 5` exits 0 after 5 seconds — so restart policy is irrelevant to the outcome. But the task explicitly requires `Never`.

### `backoffLimit` — How Many Times the Job Retries

When a Pod fails (and `restartPolicy: Never`), the Job controller creates a new Pod. It keeps trying up to `backoffLimit` times (default: **6**). After `backoffLimit` failures, the Job is marked `Failed` and no more Pods are created.

The retry interval uses exponential back-off: 10s, 20s, 40s, ... up to 6 minutes between retries. This prevents a broken Job from hammering a struggling cluster.

### `completions` and `parallelism` — Job Completion Patterns

Two fields control how a Job is considered "done":

| Field | Default | Meaning |
|-------|---------|---------|
| `completions` | 1 | How many Pods must succeed for the Job to be complete |
| `parallelism` | 1 | How many Pods can run simultaneously |

Patterns:
- `completions: 1, parallelism: 1` — one Pod, must succeed once (this task)
- `completions: 5, parallelism: 2` — 5 Pods must succeed, 2 run at a time (work queue)
- `completions: 1, parallelism: N` — race: first to succeed wins (leader election pattern)

### `activeDeadlineSeconds` — Hard Job Timeout

```yaml
spec:
  activeDeadlineSeconds: 60   # kill the entire Job if it hasn't completed in 60 seconds
```

This is a hard wall-clock timeout on the Job itself, regardless of `backoffLimit`. If the Job hasn't completed within the deadline, all running Pods are terminated and the Job is marked `DeadlineExceeded`. This is critical for preventing runaway batch Jobs in production.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl create job + dry-run + patch (Exam Technique)

`kubectl create job` exists and supports `--image` and a command after `--`. Like all `kubectl create` commands, it names the container after the resource. This task also requires `spec.template.metadata.name` — which the generator does not populate. Two separate patches are needed.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Generate the Job manifest via dry-run**
```bash
kubectl create job countdown-datacenter \
  --image=debian:latest \
  --dry-run=client -o yaml \
  -- sleep 5 > countdown-job.yaml
```

Review the generated YAML:
```bash
cat countdown-job.yaml
```

**Step 3 — Patch 1: Add `spec.template.metadata.name`**

The dry-run output has `creationTimestamp: null` in two locations:
- Under `metadata:` at **2-space** indentation (Job's own metadata)
- Under `spec.template.metadata:` at **6-space** indentation

Target the 6-space entry to insert the template name after it (GNU sed with `\n` in replacement):
```bash
sed -i 's/^      creationTimestamp: null$/      creationTimestamp: null\n      name: countdown-datacenter/' countdown-job.yaml
```

**Step 4 — Patch 2: Fix the container name**

Use the same range-restricted `sed` pattern from Day 08. The range `/- command:/,/restartPolicy:/` safely targets only the container block — the template `name:` added in Patch 1 lies outside this range:
```bash
sed -i '/- command:/,/restartPolicy:/ s/name: countdown-datacenter/name: container-countdown-datacenter/' countdown-job.yaml
```

Verify both patches:
```bash
cat countdown-job.yaml
```

Confirm:
- `metadata.name: countdown-datacenter` (Job name — unchanged)
- `spec.template.metadata.name: countdown-datacenter` (template name — added)
- `containers[0].name: container-countdown-datacenter` (container name — patched)

**Step 5 — Apply the manifest**
```bash
kubectl apply -f countdown-job.yaml
```

**Step 6 — Watch the Job and Pod**
```bash
kubectl get job countdown-datacenter -n default
kubectl get pods -n default
```

---

### Method 2 — YAML Manifest Written Directly (Recommended — Cleanest for This Task)

Two patches on a generated manifest is error-prone. For this task, writing the manifest directly is faster and more reliable:

```yaml
# countdown-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-datacenter
  namespace: default
spec:
  backoffLimit: 6                   # retry up to 6 times before marking Job Failed
  template:
    metadata:
      name: countdown-datacenter    # required by task — sets name on the pod template
    spec:
      restartPolicy: Never          # new Pod created on failure (not in-place restart)
      containers:
        - name: container-countdown-datacenter   # explicit container name required
          image: debian:latest
          command:
            - sleep
            - "5"                   # sleep 5 exits 0 — Job completes successfully
```

**Step 1 — Apply the manifest**
```bash
kubectl apply -f countdown-job.yaml
```

**Step 2 — Wait for the Job to complete**

`sleep 5` runs for 5 seconds — the Job should complete quickly:
```bash
kubectl wait job/countdown-datacenter \
  --for=condition=Complete \
  --timeout=60s \
  -n default
```

**Step 3 — Verify Job status**
```bash
kubectl get job countdown-datacenter -n default
```
Expected:
```
NAME                     COMPLETIONS   DURATION   AGE
countdown-datacenter     1/1           8s         15s
```
`COMPLETIONS=1/1` confirms the Job succeeded.

**Step 4 — Verify the Pod completed**
```bash
kubectl get pods -n default
```
Expected: Pod shows `STATUS=Completed` (not Running — the container exited cleanly).

**Step 5 — Verify Job name**
```bash
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.metadata.name}'
```
Expected: `countdown-datacenter`

**Step 6 — Verify template metadata name**
```bash
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.metadata.name}'
```
Expected: `countdown-datacenter`

**Step 7 — Verify container name**
```bash
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
```
Expected: `container-countdown-datacenter`

**Step 8 — Verify image**
```bash
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Expected: `debian:latest`

**Step 9 — Verify restart policy**
```bash
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.restartPolicy}'
```
Expected: `Never`

**Step 10 — Full describe**
```bash
kubectl describe job countdown-datacenter -n default
```

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Method 1 — Imperative dry-run + two patches
kubectl create job countdown-datacenter \
  --image=debian:latest \
  --dry-run=client -o yaml \
  -- sleep 5 > countdown-job.yaml

# Patch 1: add spec.template.metadata.name (targets 6-space creationTimestamp)
sed -i 's/^      creationTimestamp: null$/      creationTimestamp: null\n      name: countdown-datacenter/' countdown-job.yaml

# Patch 2: fix container name (range-restricted to container block)
sed -i '/- command:/,/restartPolicy:/ s/name: countdown-datacenter/name: container-countdown-datacenter/' countdown-job.yaml

kubectl apply -f countdown-job.yaml

# Method 2 — Declarative apply
kubectl apply -f countdown-job.yaml

# Job verification
kubectl get job countdown-datacenter -n default
kubectl wait job/countdown-datacenter --for=condition=Complete --timeout=60s -n default
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.metadata.name}'
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.restartPolicy}'
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
kubectl get job countdown-datacenter -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl describe job countdown-datacenter -n default

# Pod from the Job
kubectl get pods -n default -l job-name=countdown-datacenter
kubectl logs -n default -l job-name=countdown-datacenter -c container-countdown-datacenter

# All Jobs
kubectl get jobs -n default
kubectl get jobs -A

# Cleanup (run manually when done)
# Job deletion cascades to its Pods
# kubectl delete job countdown-datacenter -n default
# rm -f countdown-job.yaml
```

---

## ⚠️ Common Mistakes

1. **Missing `spec.template.metadata.name` — the field `kubectl create job` doesn't generate**
   The dry-run skeleton does not include `spec.template.metadata.name`. Most engineers apply the generated YAML directly without noticing this field is absent. The task validator checks it explicitly. This is the only field in today's task that requires a patch beyond the container name — and it sits at a different indentation level than the container name patch.

2. **Sed targeting the wrong `creationTimestamp: null` line**
   The dry-run YAML has `creationTimestamp: null` at 2-space indent (Job metadata) and 6-space indent (template metadata). A naive `sed 's/creationTimestamp: null/.../'` hits both. The patch in Method 1 uses the full line anchor (`^      creationTimestamp: null$`) targeting exactly 6 spaces — safe across both entries.

3. **Container named `countdown-datacenter` instead of `container-countdown-datacenter`**
   Same pattern as every previous task. `kubectl create job` names the container after the Job. The range-restricted sed from Day 08 targets the container block and avoids the template `name:` field added by Patch 1.

4. **Confusing `restartPolicy: Never` with "the Job never retries"**
   `Never` means the **container** is never restarted inside the same Pod. The Job controller still creates new Pods for retries — up to `backoffLimit` times (default 6). "Never retries" would require `backoffLimit: 0`. `Never` and `OnFailure` describe what happens to the Pod on container failure, not whether the Job retries at all.

5. **Expecting the Pod to show `STATUS=Running` after `sleep 5`**
   The `sleep 5` command runs for 5 seconds and exits 0. By the time you run `kubectl get pods`, the Pod is already `Completed` (or `Terminating`). Engineers who expect `Running` become confused and think the Job failed. A completed Pod in `Completed` state is the correct and expected outcome for a successful Job.

6. **Using `apiVersion: v1` or `apps/v1` for a Job**
   Job is `batch/v1` — same as CronJob. This is the second task in a row using `batch/v1`. Quick reference again: `v1` = Pod/Service/ConfigMap, `apps/v1` = Deployment/ReplicaSet/StatefulSet/DaemonSet, `batch/v1` = Job/CronJob.

7. **Deleting the Job before reading its logs**
   Once the Job and its Pod are deleted, the logs are gone. After a Job completes, the Pod enters `Completed` state but remains until manually deleted or cleaned up by `ttlSecondsAfterFinished`. Always read logs from the completed Pod before deleting the Job.

---

## 🌍 Real-World Context

Jobs are one of the most underused primitives in Kubernetes despite being one of the most useful for operations teams. Any task that has a defined start and end belongs in a Job:

- **Database schema migrations** — run Flyway or Liquibase as a Job before a Deployment rolls out
- **One-time data transformations** — backfill a new column, reindex Elasticsearch, reprocess a message queue
- **Infrastructure bootstrap** — populate a ConfigMap or Secret from an external source at cluster setup
- **Smoke tests and integration tests** — run a test suite as a Job after a Deployment completes, gate the release pipeline on Job success

In CI/CD pipelines, Jobs are often triggered by `kubectl apply` as part of a release step. The pipeline waits on `kubectl wait job/... --for=condition=Complete` before proceeding — if the Job fails, the pipeline fails and the release is blocked.

The combination of Job and CronJob covers two orthogonal scheduling dimensions:
- **CronJob** — when? (periodic schedule)
- **Job** — what? (run-to-completion workload)

When you need both: "run this task every night" → CronJob with a Job template. When you need just one: "run this task now, once" → Job directly.

---

## ❓ Interview Q&A

**Q1: What is the difference between a Job and a Deployment?**
A Deployment runs Pods indefinitely and restarts them on failure — designed for long-running services. A Job runs Pods until a specified number complete successfully, then stops — designed for finite, run-to-completion tasks. A Job that has completed does not restart its Pods; a Deployment never considers its Pods "done."

**Q2: What is the difference between `restartPolicy: Never` and `restartPolicy: OnFailure` for Jobs?**
`OnFailure` restarts the container inside the same Pod on non-zero exit — the Pod stays alive with an incrementing restart count. `Never` marks the Pod as Failed on non-zero exit and the Job controller creates a new Pod for the retry. `Never` is generally preferred for Jobs because each retry produces a separate Pod with its own preserved logs, making debugging easier. With `OnFailure`, the previous failure's logs are overwritten.

**Q3: What does `backoffLimit` control?**
`backoffLimit` (default: 6) is the number of Pod failures the Job tolerates before marking itself `Failed` and stopping retries. Each failure causes the Job controller to wait with exponential back-off (10s, 20s, 40s... up to 6 minutes) before creating the next Pod. Setting `backoffLimit: 0` means the Job fails immediately on the first Pod failure with no retries.

**Q4: What is `spec.template.metadata.name` and why would you set it on a Job?**
It sets the `name` field in the Pod template's metadata. Since Pods created by a Job have auto-generated names (job-name + random suffix), this field provides a base name embedded in the template rather than the auto-generated Pod name. It is primarily useful for traceability — making it clear from the template which Job a Pod belongs to, independent of the auto-suffix. Most validators and some tooling check this field explicitly.

**Q5: How do `completions` and `parallelism` interact?**
`completions` is the total number of successful Pod completions needed for the Job to be considered done. `parallelism` is how many Pods run simultaneously. With `completions: 5, parallelism: 2`, the Job runs two Pods at a time until 5 have succeeded. With `completions: 1, parallelism: 1` (the default and this task's configuration), one Pod runs and must succeed once.

**Q6: How do you prevent a Job from running indefinitely?**
Set `activeDeadlineSeconds` on the Job spec. Once the Job has been active for that many seconds (wall clock), all running Pods are terminated and the Job is marked `DeadlineExceeded`. This is independent of `backoffLimit` — whichever limit is hit first terminates the Job.

**Q7: How does a Job relate to a CronJob?**
A CronJob is a schedule wrapper that creates a new Job each time its cron expression triggers. The Job is the actual run-to-completion controller — the CronJob is just the scheduler. You can create a Job manually (today's task) for a one-time run, or let a CronJob create Jobs repeatedly on a schedule (Day 08). The Job template inside a CronJob is identical in structure to a standalone Job's `spec.template`.

---

## 📚 Resources

- [Kubernetes Docs — Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes Docs — Job patterns](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-patterns)
- [Kubernetes Docs — kubectl create job](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-job-em-)
- **Related days:** [Day 08](../day-08/README.md) — CronJob (wraps a Job on a schedule) | [Day 04](../day-04/README.md) — Resource limits (always set on Job containers in production)
