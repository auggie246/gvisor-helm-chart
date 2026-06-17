# gvisor-deploy

A Helm chart that installs [gVisor](https://gvisor.dev/) (`runsc` + `containerd-shim-runsc-v1`)
onto your Kubernetes nodes and wires it into containerd, so workloads can run inside the
gVisor application kernel sandbox via a `RuntimeClass`.

It is modelled on the `kata-deploy` pattern: a privileged `DaemonSet` does the per-node
installation, and a `RuntimeClass` exposes the runtime to pods. Binaries are pulled from a
**configurable** (private Nexus) repository — the chart never reaches out to the public
gVisor storage unless you point it there.

## What it does

On every selected node, the installer DaemonSet:

1. Downloads `runsc` and `containerd-shim-runsc-v1` from `<binaries.baseUrl>[/<binaries.path>]/<fileName>`.
2. Optionally verifies each binary against its `.sha512` checksum file.
3. Installs both binaries into the host bin directory (`install.binDir`, default `/usr/local/bin`).
4. Backs up `/etc/containerd/config.toml` to a timestamped copy before touching it.
5. Idempotently registers the `runsc` runtime in containerd:

   ```toml
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
     runtime_type = "io.containerd.runsc.v1"
   ```
6. Restarts containerd so the runtime is picked up.

It also creates a `RuntimeClass` (default name `gvisor`, handler `runsc`). On
`helm uninstall`, a `pre-delete` hook Job restores the newest config backup, removes the
installed binaries, and restarts containerd.

References: [gVisor install guide](https://gvisor.dev/docs/user_guide/install/) ·
[containerd quick start](https://gvisor.dev/docs/user_guide/containerd/quick_start/).

## Prerequisites

- Kubernetes nodes using **containerd** with the CRI plugin (config v2/v3).
- Nodes able to reach your private Nexus repository.
- Permission to run a **privileged**, `hostPID` DaemonSet that mounts the host filesystem.
- Helm 3+ (developed/tested against Helm v4).

## Install

### Install from the Helm repository

The packaged chart is published to GitHub Pages via the chart-releaser workflow.
Add the repo once, then install:

```sh
helm repo add gvisor-deploy https://auggie246.github.io/gvisor-helm-chart
helm repo update
helm install gvisor-deploy gvisor-deploy/gvisor-deploy \
  -n gvisor-system --create-namespace \
  --set binaries.baseUrl=https://nexus.internal.example.com/repository/gvisor-raw
```

> **Note:** GitHub Pages must be enabled once (repo Settings → Pages → branch: `gh-pages`)
> for the repository URL to serve. The release workflow creates the `gh-pages` branch on
> its first run.

### Install from local source / cloned repo

```sh
# Point the chart at your private Nexus repo and install.
helm install gvisor-deploy ./charts/gvisor-deploy \
  -n gvisor-system --create-namespace \
  --set binaries.baseUrl=https://nexus.internal.example.com/repository/gvisor-raw
```

Or use the provided example overrides (private Nexus + auth + checksum verification):

```sh
kubectl create namespace gvisor-system
kubectl -n gvisor-system create secret generic nexus-creds \
  --from-literal=username='svc-gvisor' \
  --from-literal=password='REDACTED'

helm install gvisor-deploy ./charts/gvisor-deploy -n gvisor-system \
  -f charts/gvisor-deploy/ci/private-nexus.values.yaml
```

Verify rollout:

```sh
kubectl -n gvisor-system rollout status ds/gvisor-deploy
kubectl get runtimeclass gvisor
```

## Using gVisor

Set `runtimeClassName` on a pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-gvisor
spec:
  runtimeClassName: gvisor
  containers:
    - name: nginx
      image: nginx
```

```sh
kubectl exec nginx-gvisor -- dmesg | grep -i gvisor   # should show the gVisor kernel banner
```

## Private Nexus / authentication

The binaries are downloaded from `binaries.baseUrl` (+ optional `binaries.path`). For
authenticated repos, create a secret and enable `downloadSecret` — the installer injects
`NEXUS_USERNAME` / `NEXUS_PASSWORD` and uses HTTP basic auth:

```sh
kubectl -n gvisor-system create secret generic nexus-creds \
  --from-literal=username='svc-gvisor' --from-literal=password='REDACTED'
```

```yaml
downloadSecret:
  enabled: true
  name: nexus-creds
  usernameKey: username
  passwordKey: password
```

Set `binaries.verifyChecksum: true` together with `binaries.runsc.sha512FileName` /
`binaries.shim.sha512FileName` to verify downloads.

## Private / internal CA (secure downloads)

If the repo is served behind an organization root CA, you don't need `--insecure`.
Mount the CA certificate via `caBundle` — the installer passes it to curl (`--cacert`)
/ wget (`--ca-certificate`) so TLS verifies against your CA:

```yaml
caBundle:
  enabled: true
  name: root-ca         # secret in the RELEASE namespace holding the CA cert
  key: ca.crt
binaries:
  extraDownloadArgs: []  # drop "--insecure"
```

The secret is mounted read-only. The installer fails fast if the CA file is missing
or unreadable (no silent fallback to insecure).

> **Namespace note:** Kubernetes secrets are namespaced. A `root-ca` secret in
> `flux-system` cannot be mounted into a DaemonSet in another namespace. Either
> install this chart into that namespace, or replicate the secret into the release
> namespace (Flux/kustomize sync, reflector, kyverno generate, etc.).

## Uninstall

```sh
helm uninstall gvisor-deploy -n gvisor-system
```

With `cleanup.enabled: true` (default) the pre-delete hook restores the containerd config
backup, removes the installed binaries, and restarts containerd.

## Values

### Image

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `debian` | Installer image (needs shell + curl/wget + coreutils). |
| `image.tag` | `stable-slim` | Installer image tag. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `imagePullSecrets` | `[]` | Pull secrets for the installer image. |

### Binaries (download source)

| Key | Default | Description |
| --- | --- | --- |
| `binaries.baseUrl` | `https://nexus.example.com/repository/gvisor-raw` | Base URL of the private repo (no trailing slash). **Set this.** |
| `binaries.path` | `""` | Optional sub-path appended to `baseUrl` (e.g. `release/latest/x86_64`). |
| `binaries.runsc.fileName` | `runsc` | File name of the runsc binary. |
| `binaries.runsc.sha512FileName` | `""` | Optional runsc checksum file name. |
| `binaries.shim.fileName` | `containerd-shim-runsc-v1` | File name of the shim binary. |
| `binaries.shim.sha512FileName` | `""` | Optional shim checksum file name. |
| `binaries.verifyChecksum` | `false` | Verify downloads against their `.sha512` files. |
| `binaries.extraDownloadArgs` | `[]` | Extra args passed to curl/wget (e.g. `--insecure`). |

### Download credentials

| Key | Default | Description |
| --- | --- | --- |
| `downloadSecret.enabled` | `false` | Use a secret for repo basic-auth. |
| `downloadSecret.name` | `""` | Name of the existing secret. |
| `downloadSecret.usernameKey` | `username` | Secret key holding the username. |
| `downloadSecret.passwordKey` | `password` | Secret key holding the password. |

### CA bundle (TLS against private CA)

| Key | Default | Description |
| --- | --- | --- |
| `caBundle.enabled` | `false` | Mount a CA cert and pass it to curl/wget for secure downloads. |
| `caBundle.name` | `""` | Name of the secret (in the release namespace) holding the CA cert. |
| `caBundle.key` | `ca.crt` | Key within the secret containing the PEM CA certificate. |
| `caBundle.mountPath` | `/etc/gvisor-deploy/ca` | Directory the CA secret is mounted into (read-only). |

### Install target & containerd

| Key | Default | Description |
| --- | --- | --- |
| `install.binDir` | `/usr/local/bin` | Host directory binaries are installed into. |
| `containerd.configPath` | `/etc/containerd/config.toml` | Host containerd config file. |
| `containerd.backupSuffix` | `.gvisor.bak` | Suffix for the timestamped config backup. |
| `containerd.restartContainerd` | `true` | Restart containerd after editing config. |
| `containerd.runtimeName` | `runsc` | containerd runtime table key + RuntimeClass handler. |

### RuntimeClass & scheduling

| Key | Default | Description |
| --- | --- | --- |
| `runtimeClass.create` | `true` | Create the RuntimeClass. |
| `runtimeClass.name` | `gvisor` | RuntimeClass name (`spec.runtimeClassName`). |
| `nodeSelector` | `{}` | DaemonSet node selector. |
| `tolerations` | `[]` | DaemonSet tolerations. |
| `affinity` | `{}` | DaemonSet affinity. |
| `priorityClassName` | `""` | DaemonSet priority class. |
| `resources` | `{}` | Installer container resources. |
| `updateStrategy` | `{type: RollingUpdate}` | DaemonSet update strategy. |
| `cleanup.enabled` | `true` | Run the pre-delete cleanup hook on uninstall. |

### Naming

| Key | Default | Description |
| --- | --- | --- |
| `nameOverride` | `""` | Override the chart name. |
| `fullnameOverride` | `""` | Override the fully-qualified release name. |
| `namespaceOverride` | `""` | Namespace for namespaced resources (defaults to release namespace). |

## Security considerations

This chart runs a **privileged** DaemonSet with `hostPID: true` that mounts the host root
filesystem, writes binaries to the host, rewrites `/etc/containerd/config.toml`, and
restarts containerd. Review it before deploying to production:

- Only deploy from a trusted private repository; pin and verify checksums (`verifyChecksum: true`).
- Keep Nexus credentials in a Secret (`downloadSecret`), not in plain values.
- The containerd restart briefly disrupts the CRI runtime on each node.
- Backups are timestamped; the cleanup hook restores the newest one on uninstall.
