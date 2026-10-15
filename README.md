# homelab-k8s

Kubernetes manifests for my homelab: a 4-node bare-metal cluster at home, where I break things so I don't break them at work.

## The cluster

- 4 nodes (1 control plane + 3 workers), Debian 13, Kubernetes 1.36
- Deployed with [Kubespray](https://github.com/kubernetes-sigs/kubespray), containerd + Calico
- **MetalLB** for LoadBalancer IPs on the LAN
- **Traefik** as ingress, **cert-manager** for a wildcard Let's Encrypt cert (DNS-01, Cloudflare)
- **Longhorn** for replicated block storage, **NFS** as the default class for bulk data
- **kube-prometheus-stack** (Prometheus, Grafana, Alertmanager)

```
Mac · iPhone · Apple TV
        │
     MetalLB ──► Traefik + cert-manager
                        │
   ┌──────────┬─────────┼──────────┬──────────┐
 Media      Chat      Apple      Infra
 Jellyfin   ergo/soju WeatherKit Pastebin
 tvheadend  gamja/bot Mac metrics DDNS
                        │
       Longhorn · NFS   │   Prometheus · Grafana
```

## Layout

| Path | What |
|---|---|
| `platform/` | Helm values and cluster-wide pieces: Traefik, cert-manager certificate, Longhorn, kube-prometheus-stack |
| `apps/` | Workloads: Jellyfin, tvheadend, soju + gamja (IRC bouncer + web client), IRC bot, pastebin, `wtr` (Rust API on Apple WeatherKit), Cloudflare DDNS CronJob, and a unicorn 🦄 |
| `macos/` | My MacBook as a Prometheus target (`node_exporter` + EndpointSlice) and its Grafana dashboard |

## Usage

Helm values:

```sh
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f platform/traefik-values.yaml
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace -f platform/longhorn-values.yaml
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f platform/monitoring-values.yaml
```

Plain manifests:

```sh
kubectl apply -f platform/wildcard-certificate.yaml
kubectl apply -f apps/jellyfin.yaml
```

## Secrets

Every credential in this repo is a placeholder (`CHANGE_ME`, `YOUR_TEAM_ID`, `RECORD_ID_n`…) and the domain is `example.com`. Fill them in locally or, better, create the Secrets out of band:

```sh
kubectl -n ircbot create secret generic ircbot-env --from-env-file=ircbot.env
```

Never commit real values. Files matching `*.secret.yaml` and `*.env` are git-ignored.

## Notes

Comments inside the manifests are in Spanish. They explain the *why* behind each decision.
