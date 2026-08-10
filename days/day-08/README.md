# Day 08 — Creating a CronJob in Kubernetes

> #KodeKloud Kubernetes Challenge | Day 8 of 30

---

## 📌 The Task

| Requirement       | Value                          |
|-------------------|--------------------------------|
| Kind              | CronJob                        |
| Name              | `datacenter`                   |
| Schedule          | `*/6 * * * *`                  |
| Container name    | `cron-datacenter`              |
| Image             | `httpd:latest`                 |
| Command           | `echo Welcome to xfusioncorp!` |
| Restart policy    | `OnFailure`                    |
| Namespace         | `default`                      |

---

## 🧠 Core Concepts

### The Three-Layer CronJob Hierarchy

Every CronJob task in Kubernetes spawns objects at three levels — a chain structurally similar to Deployment → ReplicaSet → Pod:

```
CronJob (datacenter)              ← the schedule definition — fires on cron trigger
  └── Job (datacenter-<hash>)     ← created each time the schedule fires
        └── Pod (datacenter-<hash>-<hash>)  ← runs the actual command
```

- **CronJob** — holds the schedule and the job template. It does not run code directly; it creates Jobs on schedule.
- **Job** — a one-time execution controller. It creates one or more Pods, waits for them to complete successfully, and tracks success/failure. Once done, the Job is retained (up to a history limit) but does not restart itself.
- **Pod** — the actual workload. For a CronJob task like `echo Welcome to xfusioncorp!`, the Pod runs, prints output, and exits with code 0.

This separation matters for observability: you check the CronJob to see the schedule, check Jobs to see past executions, and check Pods (or their logs) to see what each execution actually produced.

### Cron Schedule Syntax

A Kubernetes CronJob schedule follows the standard Unix cron format — five space-separated fields:

```
┌─────────── minute        (0–59)
│ ┌───────── hour          (0–23)
│ │ ┌─────── day of month  (1–31)
│ │ │ ┌───── month         (1–12)
│ │ │ │ ┌─── day of week   (0–6, 0=Sunday)
│ │ │ │ │
* * * * *
```

This task uses `*/6 * * * *`:

| Field | Value | Meaning |
|-------|-------|---------|
| minute | `*/6` | every 6th minute (0, 6, 12, 18, ...) |
| hour | `*` | every hour |
| day of month | `*` | every day |
| month | `*` | every month |
| day of week | `*` | every day of the week |

**Result:** the job fires every 6 minutes, around the clock, every day. Common schedule examples:

| Schedule | Meaning |
|----------|---------|
| `*/6 * * * *` | Every 6 minutes |
| `0 * * * *` | Every hour on the hour |
| `0 9 * * 1-5` | 09:00 Monday–Friday |
| `0 0 * * *` | Daily at midnight |
| `0 0 1 * *` | First day of every month at midnight |

**CronJob schedules run in UTC** unless you set `spec.timeZone` (GA in Kubernetes 1.27). In environments where business logic depends on local time, this is a silent but significant gotcha.

### Restart Policy — Why `OnFailure` and Not `Always`

The `restartPolicy` on the Pod template inside a CronJob must be either `OnFailure` or `Never`. Using `Always` is explicitly forbidden for Jobs and CronJobs and is rejected at admission. Here is why the distinction matters:

| Restart Policy | Meaning | Right context |
|---------------|---------|---------------|
| `Always` | Restart container whenever it exits for any reason, including success | Long-running services (Deployments) |
| `OnFailure` | Restart container only if it exits with a non-zero code | Batch jobs, CronJobs — expected to succeed and stop |
| `Never` | Never restart, regardless of exit code | One-shot Jobs where failure should be surfaced to the Job controller |

`Always` is designed for services that are meant to run indefinitely. A container that runs `echo` and exits with code 0 would be killed, restarted, exit 0 again, restarted again — an infinite loop. `OnFailure` means the container restarts only if it failed, and if it succeeded (exit 0), the Job marks it complete and stops.

### `concurrencyPolicy` — What Happens When a Job Runs Long

If a CronJob's previous execution is still running when the next schedule fires, `concurrencyPolicy` controls the behaviour:

| Value | Behaviour |
|-------|-----------|
| `Allow` (default) | Start a new Job regardless — multiple Jobs run in parallel |
| `Forbid` | Skip the new run — the existing Job is still running |
| `Replace` | Cancel the existing Job, start a new one |

For most production CronJobs, `Forbid` is safer than the default `Allow`. A long-running Job with `Allow` can stack up dozens of parallel executions during a slowdown, creating a thundering herd on recovery.

### History Limits — How Many Past Jobs Are Retained

Two fields control how many completed Jobs are kept:

```yaml
spec:
  successfulJobsHistoryLimit: 3   # keep 3 successful Job records (default: 3)
  failedJobsHistoryLimit: 1       # keep 1 failed Job record (default: 1)
```

Once the limit is exceeded, the oldest Job (and its Pod) is deleted. Setting both to `0` means no history — no logs accessible after execution, no audit trail. In production, keep at least 3 successful and 1 failed for debugging.

### `apiVersion: batch/v1`

CronJob (and Job) lives in the `batch` API group — not `apps/v1` (Deployments, ReplicaSets) and not `v1` (Pods, Services). A wrong `apiVersion` produces a clear API server error but wastes time under lab pressure.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl create cronjob + dry-run (Exam Technique)

`kubectl create cronjob` exists and supports `--image`, `--schedule`, `--restart`, and a command after `--`. Like `kubectl run`, it names the container after the CronJob — the same dry-run + patch technique from Day 01 applies.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Generate the CronJob manifest via dry-run**
```bash
kubectl create cronjob datacenter \
  --image=httpd:latest \
  --schedule="*/6 * * * *" \
  --restart=OnFailure \
  --dry-run=client -o yaml \
  -- echo "Welcome to xfusioncorp!" > datacenter-cronjob.yaml
```

Review the generated manifest:
```bash
cat datacenter-cronjob.yaml
```

**Step 3 — Patch the container name**

The generated YAML has `name: datacenter` in multiple places:
- `metadata.name: datacenter` — the CronJob name (2-space indent — leave it)
- `jobTemplate.metadata.name: datacenter` — the Job template name (6-space indent — leave it)
- `containers[].name: datacenter` — the container name (deep indent, after `- command:`) — **patch this**

Use a range-restricted `sed` to target only the container name entry, not the metadata entries:
```bash
sed -i '/- command:/,/restartPolicy:/ s/name: datacenter/name: cron-datacenter/' datacenter-cronjob.yaml
```

Verify the patch:
```bash
cat datacenter-cronjob.yaml
```

Confirm `cron-datacenter` appears exactly once, and `datacenter` still appears in `metadata.name` and `jobTemplate.metadata`.

**Step 4 — Apply the manifest**
```bash
kubectl apply -f datacenter-cronjob.yaml
```

**Step 5 — Verify CronJob created**
```bash
kubectl get cronjob datacenter -n default
```

---

### Method 2 — YAML Manifest Written Directly (Declarative — Production Grade)

```yaml
# datacenter-cronjob.yaml
apiVersion: batch/v1            # NOT apps/v1 — CronJob is in the batch API group
kind: CronJob
metadata:
  name: datacenter
  namespace: default
spec:
  schedule: "*/6 * * * *"       # every 6 minutes
  concurrencyPolicy: Forbid     # skip next run if current is still executing
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure   # OnFailure or Never only — Never use Always
          containers:
            - name: cron-datacenter  # explicit container name required by task
              image: httpd:latest
              command:
                - echo
                - "Welcome to xfusioncorp!"
```

**Step 1 — Apply the manifest**
```bash
kubectl apply -f datacenter-cronjob.yaml
```

**Step 2 — Verify the CronJob**
```bash
kubectl get cronjob datacenter -n default
```
Expected:
```
NAME         SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
datacenter   */6 * * * *   False     0        <none>          10s
```
`LAST SCHEDULE` shows `<none>` until the first scheduled trigger fires.

**Step 3 — Verify schedule and spec details**
```bash
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.schedule}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'
```

**Step 4 — Manually trigger a Job to test without waiting for the schedule**
```bash
kubectl create job datacenter-manual-test \
  --from=cronjob/datacenter \
  -n default
```

**Step 5 — Watch the triggered Job and Pod**
```bash
kubectl get jobs -n default
kubectl get pods -n default
```

**Step 6 — Check logs from the triggered Pod**
```bash
# Get the pod name
POD=$(kubectl get pods -n default -l job-name=datacenter-manual-test \
  -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs "${POD}" -n default -c cron-datacenter
```
Expected output: `Welcome to xfusioncorp!`

**Step 7 — Full describe**
```bash
kubectl describe cronjob datacenter -n default
```

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Method 1 — Imperative dry-run + patch
kubectl create cronjob datacenter \
  --image=httpd:latest \
  --schedule="*/6 * * * *" \
  --restart=OnFailure \
  --dry-run=client -o yaml \
  -- echo "Welcome to xfusioncorp!" > datacenter-cronjob.yaml
sed -i '/- command:/,/restartPolicy:/ s/name: datacenter/name: cron-datacenter/' datacenter-cronjob.yaml
kubectl apply -f datacenter-cronjob.yaml

# Method 2 — Declarative apply
kubectl apply -f datacenter-cronjob.yaml

# CronJob verification
kubectl get cronjob datacenter -n default
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.schedule}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}'
kubectl get cronjob datacenter -n default \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'
kubectl describe cronjob datacenter -n default

# Manually trigger a Job from the CronJob (don't wait 6 minutes)
kubectl create job datacenter-test \
  --from=cronjob/datacenter \
  -n default

# Watch triggered Jobs and Pods
kubectl get jobs -n default
kubectl get pods -n default -w

# Get logs from the completed Pod
kubectl logs <pod-name> -n default -c cron-datacenter

# All CronJobs in the cluster
kubectl get cronjobs -n default
kubectl get cronjobs -A

# Suspend a CronJob (pause without deleting)
kubectl patch cronjob datacenter -n default -p '{"spec":{"suspend":true}}'

# Resume a suspended CronJob
kubectl patch cronjob datacenter -n default -p '{"spec":{"suspend":false}}'

# Cleanup (run manually when done)
# kubectl delete cronjob datacenter -n default
# kubectl delete job datacenter-test -n default
# rm -f datacenter-cronjob.yaml
```

---

## ⚠️ Common Mistakes

1. **Container named `datacenter` instead of `cron-datacenter`**
   `kubectl create cronjob datacenter` names the container `datacenter` — same pattern as `kubectl run` and `kubectl create deployment`. The dry-run + `sed` patch from Day 01 applies again, but the CronJob YAML is deeply nested. The range-restricted sed (`/- command:/,/restartPolicy:/`) targets only the container entry, avoiding the CronJob's `metadata.name` and `jobTemplate.metadata` entries.

2. **Using `restartPolicy: Always` — rejected at admission**
   `Always` is explicitly invalid for Job and CronJob Pod templates. The API server rejects it immediately with a validation error. `OnFailure` restarts on non-zero exit codes only — correct for batch tasks. `Never` surfaces failure to the Job controller without retrying — appropriate for one-shot tasks where you want to inspect the failure before retrying.

3. **Wrong `apiVersion` — using `apps/v1` or `v1`**
   CronJob is in `batch/v1`. Using `apps/v1` produces `no matches for kind "CronJob" in version "apps/v1"`. Quick reference: `v1` = core group (Pods, Services, ConfigMaps); `apps/v1` = workload controllers (Deployment, ReplicaSet, StatefulSet, DaemonSet); `batch/v1` = batch workloads (Job, CronJob).

4. **Forgetting the CronJob does not run immediately**
   After `kubectl apply`, the CronJob shows `LAST SCHEDULE: <none>` and `ACTIVE: 0`. Nothing has run yet — it waits for the next schedule trigger. In a lab with a 6-minute schedule, you may wait up to 6 minutes to see a Job and Pod created. Use `kubectl create job --from=cronjob/datacenter` to trigger an immediate run for testing.

5. **CronJob schedule is in UTC**
   `*/6 * * * *` fires every 6 minutes relative to UTC. In a lab this is irrelevant, but in production a CronJob set to `0 9 * * *` in a US Eastern environment actually runs at 14:00 UTC, not 09:00 local. Set `spec.timeZone` (Kubernetes 1.27+) to specify a local timezone explicitly rather than calculating UTC offsets manually.

6. **`concurrencyPolicy: Allow` (default) enabling job pile-up**
   The default `Allow` means if one execution is still running when the next trigger fires, both run in parallel. For a long-running task this compounds — slow execution leads to stacked Jobs which slow execution further. In production, default to `Forbid` (skip the new run) or `Replace` (cancel the old run and start fresh) based on whether job freshness or job completion matters more.

7. **Checking logs on a Pod that has already been cleaned up**
   After `successfulJobsHistoryLimit` successful Jobs are created, the oldest is deleted — taking its Pod with it. If you check logs after the retention window closes, the Pod is gone. Always check logs while the Job is still within the history limit, or pipe logs to persistent storage (Elasticsearch, Loki, CloudWatch) in production.

---

## 🌍 Real-World Context

CronJobs are the Kubernetes-native replacement for cron entries in `/etc/crontab` on a VM. Common production use cases:

- **Database backups** — `pg_dump` to S3 every night at 02:00
- **Report generation** — aggregate metrics and email a summary every Monday 08:00
- **Cache warming** — pre-populate Redis before business hours
- **Certificate rotation** — trigger cert-manager or custom renewal logic on a schedule
- **Data pipeline triggers** — kick off a Spark or Flink job to process overnight batches
- **Cleanup jobs** — purge old log files, expired sessions, or stale data on a schedule

In production, CronJobs are usually wrapped with:

```yaml
spec:
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 3
  startingDeadlineSeconds: 300   # if the job hasn't started within 5 min of schedule, skip
  jobTemplate:
    spec:
      backoffLimit: 2            # retry failed pods up to 2 times before marking the Job failed
      activeDeadlineSeconds: 600 # kill the Job if it runs longer than 10 minutes
```

`startingDeadlineSeconds` is particularly important in clusters under heavy load — if the CronJob controller is delayed and misses the schedule window, this controls how late a Job is still allowed to start.

---

## ❓ Interview Q&A

**Q1: What is the relationship between a CronJob, a Job, and a Pod?**
CronJob is the schedule definition — it fires on the configured cron trigger and creates a Job each time. Job is a one-time execution controller — it creates one or more Pods, waits for them to complete, and tracks success or failure. Pod is the actual workload running the command. You inspect the CronJob for schedule info, Jobs for execution history, and Pods (logs) for actual output.

**Q2: Why can't you use `restartPolicy: Always` in a CronJob?**
`Always` restarts a container whenever it exits, including successful exit (code 0). A batch command like `echo` exits 0 immediately — with `Always`, it would restart in an infinite loop. `OnFailure` only restarts on non-zero exit codes, letting a successful run complete cleanly. The Kubernetes API server explicitly rejects `Always` for Job and CronJob Pod templates at admission.

**Q3: How do you test a CronJob without waiting for the schedule to fire?**
`kubectl create job <name> --from=cronjob/<cronjob-name> -n <namespace>` triggers an immediate Job execution from the CronJob's template. This is the standard technique for testing CronJob logic without a 6-hour wait.

**Q4: What does `concurrencyPolicy: Forbid` do and when would you use it?**
`Forbid` causes the CronJob controller to skip the new scheduled run if the previous Job is still executing. Use it when job overlap is harmful — for example, a database backup that locks tables, or a pipeline that processes a queue (running two instances would duplicate work). Use `Allow` when jobs are idempotent and can run in parallel safely.

**Q5: What is `startingDeadlineSeconds` and why does it matter in production?**
If the CronJob controller is delayed (due to cluster load, control plane restart, or etcd lag) and cannot create a Job within `startingDeadlineSeconds` of the scheduled time, it skips that execution entirely. Without it, a delayed controller could trigger many missed Jobs all at once on recovery — a thundering herd. Setting `startingDeadlineSeconds: 300` limits recovery to Jobs that are at most 5 minutes late.

**Q6: How do you pause a CronJob temporarily without deleting it?**
Set `spec.suspend: true` on the CronJob: `kubectl patch cronjob <name> -p '{"spec":{"suspend":true}}'`. No new Jobs are created while suspended. Resume with `suspend: false`. This is cleaner than deletion for planned maintenance windows.

**Q7: What happens to logs after a CronJob's Job is cleaned up by `successfulJobsHistoryLimit`?**
Once a Job is deleted (past the history limit), its Pods are garbage-collected and logs are gone — unless you have a centralised log shipper (Fluentd, Promtail, Filebeat) collecting container logs to an external store (Elasticsearch, Loki, CloudWatch) before the container exits. In production, CronJob logs should always flow to persistent storage, not just the container runtime.

---

## 📚 Resources

- [Kubernetes Docs — CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Kubernetes Docs — Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes Docs — CronJob timezone support](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#time-zones)
- [Crontab Guru — schedule expression validator](https://crontab.guru/)
- **Related days:** [Day 07](../day-07/README.md) — ReplicaSet (similar three-layer hierarchy pattern) | [Day 04](../day-04/README.md) — Resource limits (always set on CronJob containers in production)
