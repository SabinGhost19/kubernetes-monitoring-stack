
---

# Installing Prometheus and Grafana on Kubernetes Using Helm

This guide explains how to install **Prometheus** and **Grafana** on a Kubernetes cluster using Helm charts.

---

## Step 1: Add the Prometheus Helm Chart Repository

Run the following commands to add the Prometheus Helm chart:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**Output:**

```bash
helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "hashicorp" chart repository
...Successfully got an update from the "grafana" chart repository
...Successfully got an update from the "prometheus-community" chart repository
Update Complete. ⎈Happy Helming!⎈
```

We have downloaded the latest version of the Prometheus chart.

---

## Step 2: Install Prometheus Helm Chart on Kubernetes

To install the Prometheus Helm chart, run the following command:

```bash
helm install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace
```

**Output:**

```bash
NAME: prometheus
LAST DEPLOYED: Tue Dec 19 11:04:13 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Prometheus server can be accessed via port 80 on the following DNS name from within your cluster:
prometheus-server.default.svc.cluster.local
```

### Access Prometheus

**Get the Prometheus server URL:**

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace default port-forward $POD_NAME 9090
```

**Alertmanager:**

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=alertmanager,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace default port-forward $POD_NAME 9093
```

**PushGateway:**

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app=prometheus-pushgateway,component=pushgateway" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace default port-forward $POD_NAME 9091
```

---

### Important Note

```text
#################################################################################
######   WARNING: Pod Security Policy has been disabled by default since    #####
######            it deprecated after k8s 1.25+. use                        #####
######            (index .Values "prometheus-node-exporter" "rbac"          #####
###### .          "pspEnabled") with (index .Values                         #####
######            "prometheus-node-exporter" "rbac" "pspAnnotations")       #####
######            in case you still need it.                                #####
#################################################################################
```

For more information on running Prometheus, visit:
🔗 [https://prometheus.io/](https://prometheus.io/)

---

## Step 3: Install Grafana

Now that Prometheus is installed, let's set up **Grafana** and integrate it with Prometheus as the primary data source.

---

### Search for the Grafana Helm Chart

Run the following command to search for Grafana charts:

```bash
helm search hub grafana
```

**Output (truncated):**

```
URL                                                     CHART VERSION   APP VERSION   DESCRIPTION
https://artifacthub.io/packages/helm/grafana/gr...      7.0.19          10.2.2        The leading tool for querying and visualizing t...
...
```

You can also visit [Artifact Hub](https://artifacthub.io/) to explore the official Grafana Helm chart.

---

###  Add the Grafana Helm Repository

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

---

### Install Grafana Helm Chart on Kubernetes

Run the following command to install Grafana:

```bash
helm install grafana grafana/grafana
```

**Output:**

```bash
NAME: grafana
LAST DEPLOYED: Tue Dec 19 12:36:38 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get your 'admin' user password by running:

   kubectl get secret --namespace default grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

2. The Grafana server can be accessed via port 80 on the following DNS name from within your cluster:

   grafana.default.svc.cluster.local

   Get the Grafana URL to visit by running these commands in the same shell:
     export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
     kubectl --namespace default port-forward $POD_NAME 3000

3. Login with the password from step 1 and the username: admin
```

---

### Verify Grafana Services

Once Grafana is installed, list its services using:

```bash
kubectl get service
```

**Output:**

```bash
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
grafana       ClusterIP   10.104.22.18    <none>        80/TCP    4m6s
```

---



### GET ADMIN USER PASSWORD:

```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```