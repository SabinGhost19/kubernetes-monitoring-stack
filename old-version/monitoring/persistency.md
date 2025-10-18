# Persistent Storage for Prometheus & Grafana on Kubernetes

## 1. Persistent Storage for Prometheus TSDB

Prometheus stores its time-series data in a local volume (TSDB). To make it persist across pod restarts or upgrades, use a **PersistentVolumeClaim (PVC)**.

### Example: Configure in the Helm `values.yaml`

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: [ "ReadWriteOnce" ]
          storageClassName: <your-storage-class> # e.g. "microk8s-hostpath", "ceph-rbd"
          resources:
            requests:
              storage: 50Gi # Adjust based on data retention
```

- Run:
  ```bash
  helm install observability prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml
  ```
- The Operator will dynamically create a PVC for Prometheus. **Prometheus data will persist** even if the pod gets recreated!

**To migrate existing data:**
- If you used another PVC before, mount the same name in the new setup. Alternatively, copy old TSDB `/data` from the former PVC into the new one.
- Backup manually with:
  ```bash
  kubectl cp monitoring/prometheus-server-xxxx:/data /YOUR/BACKUP/PATH
  # Restore with 'kubectl cp' into new pod volume
  ```


## 2. Persistent Storage for Grafana Dashboards & Config

Grafana stores custom dashboards, configs, users, and API keys – all under `/var/lib/grafana`.

### Helm `values.yaml` example

```yaml
grafana:
  persistence:
    enabled: true
    type: pvc
    storageClassName: <your-storage-class>
    accessModes:
      - ReadWriteOnce
    size: 10Gi
```

- This automatically creates and mounts a PVC, making **all dashboard edits, users and data persistent**.
- On pod restart or upgrade, all data remains on disk.

**Export/Import Dashboards for migration**
- In legacy Grafana, export dashboards as JSON from the UI or using API:
  ```bash
  curl -H "Authorization: Bearer <API_KEY>" https://<grafana-url>/api/dashboards/uid/<dashboard_uid>
  ```
- In new Grafana, import from UI or script.
- For automated provisioning, mount dashboards as ConfigMaps:
  ```yaml
  grafana:
    dashboards:
      default:
        custom: |
          <dashboard JSON here>
  ```


## 3. Technical Steps – Production Ready

1. **Ensure your StorageClass** is set up and working (test with a dummy PVC):
   ```bash
   kubectl get storageclass
   kubectl describe storageclass <your-storage-class>
   kubectl apply -f test-pvc.yaml
   kubectl get pvc -n monitoring
   ```
2. **Set up values.yaml** as above for Operator deployment with persistence for Prometheus & Grafana.
3. **Install/upgrade the stack:**
   ```bash
   helm upgrade --install observability prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml
   ```
4. **Verify PVCs & Mounts:**
   ```bash
   kubectl get pvc -n monitoring
   kubectl describe pod <grafana-pod> -n monitoring | grep /var/lib/grafana
   kubectl describe pod <prometheus-pod> -n monitoring | grep /data
   ```
5. **Backup/Restore procedures:**
   - Back up PV/PVC data before major upgrades to external storage (rsync, cp).
   - Automate dashboard backup via Grafana API if needed.


## 4. Additional Notes
- Always use PVCs with proper storage class for all data-critical workloads.
- In multi-tenant environments, use separate PVCs per tenant or monitoring instance.
- **Avoid using ephemeral emptyDir volumes** for production!
- For air-gapped/backup strategies: regularly snapshot PVCs (storage backend specific)

----