# Production-Grade Kubernetes Logging Architecture
## Complete Guide: JSON Logs, Fluent Bit/Fluentd Pipeline, OpenSearch Integration

**Last Updated:** October 14, 2025  
**Version:** 1.0  
**Author:** DevOps/Platform Engineering Team

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Principles](#architecture-principles)
3. [Document Structure Standards](#document-structure-standards)
4. [Fluent Bit vs Fluentd - Roles and Responsibilities](#fluent-bit-vs-fluentd---roles-and-responsibilities)
5. [Log Sources - Concrete Examples](#log-sources---concrete-examples)
6. [OpenSearch Integration](#opensearch-integration)
7. [Index Strategy](#index-strategy)
8. [Custom Collector Implementation](#custom-collector-implementation)
9. [Operational Best Practices](#operational-best-practices)
10. [Configuration Examples](#configuration-examples)
11. [Troubleshooting](#troubleshooting)

---

## Overview

This document describes a production-grade logging architecture for Kubernetes environments, covering:

- **JSON-structured logs** with ECS-like schema
- **Fluent Bit** (lightweight agents on nodes) for log collection
- **Fluentd** (aggregator) for enrichment and transformation
- **OpenSearch** for storage, indexing, and analysis
- **Custom collectors** for Kubernetes API state snapshots

### Key Goals

- **Consistency:** Uniform document structure across all log sources
- **Performance:** Optimized indexing and query performance
- **Scalability:** Handle 100k+ events/second
- **Observability:** Full visibility into cluster state and application behavior
- **Compliance:** Audit logs with proper retention policies

---

## Architecture Principles

### 1. Mandatory Fields in Every Document

Every JSON document sent to OpenSearch must include:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `@timestamp` | ISO8601 UTC | Event time (used by OpenSearch for time-series) | `2025-10-13T12:00:00.000Z` |
| `message` | string | Human-readable event description | `"db timeout"` |
| `log.level` | keyword | Log severity | `info`, `warn`, `error`, `debug` |
| `service.name` | keyword | Application/component name | `orders-service`, `kubelet` |
| `host.name` | keyword | Node hostname | `worker-02` |
| `host.ip` | ip | Node IP address | `10.0.0.5` |
| `agent.name` | keyword | Log collection agent | `fluent-bit` |
| `agent.version` | keyword | Agent version | `2.0.14` |

### 2. Kubernetes-Specific Fields

```json
{
  "kubernetes": {
    "namespace": "prod",
    "pod": {
      "name": "orders-5f6d7c8",
      "uid": "1111-2222-3333-4444"
    },
    "container": {
      "name": "orders",
      "id": "docker://abcd1234..."
    },
    "node": "worker-02",
    "resource_kind": "Pod|NetworkPolicy|Role|Event",
    "spec": { /* full resource specification */ }
  }
}
```

### 3. Event Classification (Security/Audit)

```json
{
  "event": {
    "action": "create|delete|update|exec|connect",
    "category": "authentication|authorization|network|system",
    "outcome": "success|failure",
    "kind": "k8s.audit|security|application"
  }
}
```

### 4. Raw Data Preservation

Always include `raw` field for debugging:

```json
{
  "raw": "{\"time\":\"2025-10-13T12:01:05.123Z\",\"level\":\"error\",\"msg\":\"db timeout\"}"
}
```

---

## Document Structure Standards

### Canonical Document Shape

Use this structure for **all** logs:

```json
{
  "@timestamp": "2025-10-13T12:10:00.000Z",
  "message": "short description or message",
  "service.name": "orders-service | kubelet | kube-apiserver | collector",
  "agent.name": "fluent-bit",
  "agent.version": "2.0.14",
  "host.name": "worker-02",
  "host.ip": "10.0.0.5",
  "log.level": "info|warn|error",
  "event": {
    "action": "create|delete|connect|exec",
    "category": "authentication|authorization|network|system",
    "outcome": "success|failure"
  },
  "kubernetes": {
    "resource_kind": "Pod|NetworkPolicy|Role|Event",
    "namespace": "prod",
    "pod": {
      "name": "orders-5f6d7c",
      "uid": "uuid-here"
    },
    "container": {
      "name": "orders",
      "id": "docker://..."
    },
    "node": "worker-02",
    "spec": { /* optional, full spec */ }
  },
  "user": {
    "name": "alice",
    "uid": "user-uid",
    "groups": ["system:authenticated"]
  },
  "audit": {
    "id": "a1b2c3d4"
  },
  "snapshot": {
    "type": "k8s_state|networkpolicy",
    "id": "snapshot-2025-10-13T12:10:00Z"
  },
  "trace.id": "distributed-trace-id",
  "request.id": "request-correlation-id",
  "raw": "{...original...}"
}
```

---

## Fluent Bit vs Fluentd - Roles and Responsibilities

### Fluent Bit (Lightweight Agent - Per Node)

**Role:** First-stage log collection from container runtime and system logs.

**Responsibilities:**
- Tail log files (`/var/log/containers/*.log`)
- Read container stdout/stderr via CRI
- Basic parsing (JSON, regex, timestamp normalization)
- Add Kubernetes metadata (via kubelet API)
- Filter/drop unwanted logs
- Forward to Fluentd aggregator

**Configuration Example:**

```ini
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.container.*
    Refresh_Interval  5
    Mem_Buf_Limit     5MB
    Skip_Long_Lines   On

[INPUT]
    Name              systemd
    Tag               node.systemd
    Read_From_Tail    On
    Strip_Underscores On

[PARSER]
    Name        docker
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z

[FILTER]
    Name                kubernetes
    Match               kube.container.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Merge_Log           On
    Keep_Log            Off
    K8S-Logging.Parser  On
    K8S-Logging.Exclude On

[OUTPUT]
    Name        forward
    Match       *
    Host        fluentd-aggregator.logging.svc
    Port        24224
    Retry_Limit 3
```

**Key Points:**
- Runs as DaemonSet (one pod per node)
- Low memory footprint (~50MB)
- Fast and efficient
- Limited transformation capabilities

---

### Fluentd (Aggregator - Centralized)

**Role:** Second-stage aggregation, enrichment, and routing.

**Responsibilities:**
- Receive logs from all Fluent Bit agents
- Complex transformations (field mapping, enrichment)
- Apply ECS schema normalization
- GeoIP lookup, user lookup
- Data redaction/masking
- Buffering and retry logic
- Route to multiple backends (OpenSearch, S3, etc.)

**Configuration Example:**

```xml
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

<filter kube.container.**>
  @type record_transformer
  enable_ruby true
  <record>
    @timestamp ${time.iso8601}
    service.name ${record["kubernetes"]["labels"]["app"] || "unknown"}
    host.name ${record["kubernetes"]["host"]}
    agent.name "fluent-bit"
  </record>
</filter>

<filter kube.container.**>
  @type parser
  key_name log
  reserve_data true
  <parse>
    @type json
  </parse>
</filter>

<match kube.container.**>
  @type opensearch
  host opensearch-cluster.logging.svc
  port 9200
  scheme https
  ssl_verify true
  user "#{ENV['OPENSEARCH_USER']}"
  password "#{ENV['OPENSEARCH_PASSWORD']}"
  index_name logs-containers-%Y.%m.%d
  type_name _doc
  logstash_format true
  include_timestamp true
  reconnect_on_error true
  reload_on_failure true
  reload_connections false
  <buffer>
    @type file
    path /var/log/fluentd-buffers/opensearch.buffer
    flush_mode interval
    flush_interval 5s
    chunk_limit_size 5M
    retry_wait 10s
    retry_max_times 3
    overflow_action block
  </buffer>
</match>
```

**Key Points:**
- Runs as Deployment (2-3 replicas for HA)
- Memory usage ~500MB-2GB
- Rich plugin ecosystem
- Complex transformations possible

---

## Log Sources - Concrete Examples

### A. Container Application Logs (JSON stdout)

**Raw log file (`/var/log/containers/orders-5f6d7c8_prod_orders-abc123.log`):**

```json
{"time":"2025-10-13T12:01:05.123Z","level":"error","msg":"db timeout","request_id":"abc-123","user_id":"user-456"}
```

**Fluent Bit parsing → OpenSearch document:**

```json
{
  "@timestamp": "2025-10-13T12:01:05.123Z",
  "message": "db timeout",
  "log.level": "error",
  "service.name": "orders-service",
  "agent.name": "fluent-bit",
  "agent.version": "2.0.14",
  "host.name": "worker-02",
  "host.ip": "10.0.0.25",
  "kubernetes": {
    "namespace": "prod",
    "pod": {
      "name": "orders-5f6d7c8",
      "uid": "1111-2222-3333-4444"
    },
    "container": {
      "name": "orders",
      "id": "docker://abc123def456"
    },
    "node": "worker-02",
    "labels": {
      "app": "orders-service",
      "version": "v2.1.0"
    }
  },
  "trace.id": "abcd-1234-trace",
  "request.id": "abc-123",
  "user.id": "user-456",
  "raw": "{\"time\":\"2025-10-13T12:01:05.123Z\",\"level\":\"error\",\"msg\":\"db timeout\",\"request_id\":\"abc-123\",\"user_id\":\"user-456\"}"
}
```

**Use cases:**
- Full-text search on `message`
- Filter by `log.level: error`
- Aggregate by `service.name`
- Trace requests via `request.id`

---

### B. Kubelet Logs (System Component)

**Raw log (`/var/log/kubelet.log`):**

```
Oct 13 12:02:11 worker-02 kubelet[1234]: I1013 12:02:11.456789 1234 pod_workers.go:1234] SyncLoop (ADD, "api:default/nginx-7"): starting
```

**Parsed document:**

```json
{
  "@timestamp": "2025-10-13T12:02:11.456Z",
  "message": "SyncLoop (ADD, \"api:default/nginx-7\"): starting",
  "log.level": "info",
  "service.name": "kubelet",
  "agent.name": "fluent-bit",
  "host.name": "worker-02",
  "host.ip": "10.0.0.25",
  "log.origin.file.path": "/var/log/kubelet.log",
  "kubernetes": {
    "event": "pod.add",
    "pod": {
      "name": "nginx-7",
      "namespace": "default"
    }
  },
  "process.name": "kubelet",
  "process.pid": 1234,
  "raw": "Oct 13 12:02:11 worker-02 kubelet[1234]: I1013 12:02:11.456789 1234 pod_workers.go:1234] SyncLoop (ADD, \"api:default/nginx-7\"): starting"
}
```

---

### C. Syslog (Operating System)

**Raw log (`/var/log/syslog`):**

```
Oct 13 12:03:00 worker-02 CRON[3456]: (root) CMD (/usr/local/bin/backup.sh)
```

**Parsed document:**

```json
{
  "@timestamp": "2025-10-13T12:03:00.000Z",
  "message": "(root) CMD (/usr/local/bin/backup.sh)",
  "log.level": "info",
  "service.name": "cron",
  "agent.name": "fluent-bit",
  "host.name": "worker-02",
  "host.ip": "10.0.0.25",
  "log.origin.file.path": "/var/log/syslog",
  "process.name": "CRON",
  "process.pid": 3456,
  "user.name": "root",
  "raw": "Oct 13 12:03:00 worker-02 CRON[3456]: (root) CMD (/usr/local/bin/backup.sh)"
}
```

---

### D. Kubernetes Audit Logs (kube-apiserver)

**Raw audit log (`/var/log/kube-apiserver/audit.log`):**

```json
{
  "kind": "Event",
  "apiVersion": "audit.k8s.io/v1",
  "level": "RequestResponse",
  "auditID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/prod/pods",
  "verb": "create",
  "user": {
    "username": "alice",
    "uid": "alice-uid-123",
    "groups": ["system:authenticated", "developers"]
  },
  "sourceIPs": ["10.0.0.5"],
  "userAgent": "kubectl/v1.28.0",
  "objectRef": {
    "resource": "pods",
    "namespace": "prod",
    "name": "nginx-7",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "metadata": {},
    "code": 201
  },
  "requestObject": { /* full pod spec */ },
  "responseObject": { /* created pod object */ },
  "requestReceivedTimestamp": "2025-10-13T12:05:21.123456Z",
  "stageTimestamp": "2025-10-13T12:05:21.234567Z"
}
```

**OpenSearch-optimized document:**

```json
{
  "@timestamp": "2025-10-13T12:05:21.234Z",
  "message": "User alice created pod nginx-7 in namespace prod",
  "event": {
    "action": "create",
    "kind": "k8s.audit",
    "category": "authorization",
    "outcome": "success"
  },
  "audit": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "stage": "ResponseComplete",
    "level": "RequestResponse"
  },
  "request": {
    "uri": "/api/v1/namespaces/prod/pods",
    "verb": "create"
  },
  "kubernetes": {
    "namespace": "prod",
    "resource": "pods",
    "resource_kind": "Pod",
    "name": "nginx-7",
    "api_version": "v1"
  },
  "user": {
    "name": "alice",
    "uid": "alice-uid-123",
    "groups": ["system:authenticated", "developers"]
  },
  "source": {
    "ip": ["10.0.0.5"]
  },
  "user_agent": "kubectl/v1.28.0",
  "response": {
    "code": 201,
    "status": "success"
  },
  "duration_ms": 111,
  "raw": "{...full audit event...}"
}
```

**Critical audit queries:**
- Failed authentication attempts: `event.outcome: failure AND event.category: authentication`
- Privilege escalations: `event.action: (create OR update) AND kubernetes.resource: (roles OR clusterroles)`
- Secret access: `kubernetes.resource: secrets`
- Pod exec events: `event.action: connect AND request.uri: */exec`

---

### E. NetworkPolicy Snapshots (Custom Collector)

**Collector logic:** Run `kubectl get networkpolicies -A -o json` every 5 minutes.

**Document per NetworkPolicy:**

```json
{
  "@timestamp": "2025-10-13T12:10:00.000Z",
  "message": "NetworkPolicy snapshot: deny-all-ingress in prod namespace",
  "snapshot": {
    "type": "networkpolicy",
    "id": "snapshot-np-uid-1234-2025-10-13T12:10:00Z",
    "interval_sec": 300
  },
  "kubernetes": {
    "resource_kind": "NetworkPolicy",
    "namespace": "prod",
    "name": "deny-all-ingress",
    "uid": "np-uid-1234-5678-90ab-cdef",
    "creation_timestamp": "2025-10-01T08:00:00Z",
    "spec": {
      "podSelector": {},
      "policyTypes": ["Ingress", "Egress"],
      "ingress": [],
      "egress": [
        {
          "to": [{"namespaceSelector": {"matchLabels": {"name": "kube-system"}}}],
          "ports": [{"protocol": "UDP", "port": 53}]
        }
      ]
    }
  },
  "collector": {
    "name": "k8s-state-collector",
    "type": "deployment",
    "version": "1.0.0",
    "node": "master-01"
  },
  "raw": "{...full NetworkPolicy JSON...}"
}
```

**Alternative: Aggregated snapshot (all NetworkPolicies):**

```json
{
  "@timestamp": "2025-10-13T12:10:00.000Z",
  "message": "Kubernetes state snapshot: 12 NetworkPolicies, 40 Roles, 230 Pods",
  "snapshot": {
    "type": "k8s_state",
    "id": "snapshot-2025-10-13T12:10:00Z",
    "interval_sec": 300
  },
  "kubernetes": {
    "networkpolicies_count": 12,
    "roles_count": 40,
    "rolebindings_count": 85,
    "clusterroles_count": 15,
    "clusterrolebindings_count": 30,
    "pods_count": 230,
    "services_count": 45
  },
  "k8s_state": {
    "networkpolicies": [
      {
        "namespace": "prod",
        "name": "deny-all-ingress",
        "uid": "np-uid-1234",
        "ingress_rules": 0,
        "egress_rules": 1
      },
      {
        "namespace": "dev",
        "name": "allow-from-istio",
        "uid": "np-uid-2345",
        "ingress_rules": 2,
        "egress_rules": 0
      }
    ],
    "roles": [
      {
        "namespace": "prod",
        "name": "pod-reader",
        "uid": "role-uid-123",
        "rules_count": 3
      }
    ]
  },
  "collector": {
    "name": "k8s-state-collector",
    "version": "1.0.0"
  }
}
```

---

### F. Kubernetes Events (Real-time)

**Raw event (watch API):**

```json
{
  "type": "Warning",
  "reason": "FailedScheduling",
  "message": "0/3 nodes are available: 3 Insufficient cpu.",
  "metadata": {
    "name": "nginx-7.abcd1234",
    "namespace": "prod"
  },
  "involvedObject": {
    "kind": "Pod",
    "name": "nginx-7",
    "namespace": "prod",
    "uid": "pod-uid-5678"
  },
  "firstTimestamp": "2025-10-13T12:15:00Z",
  "lastTimestamp": "2025-10-13T12:15:30Z",
  "count": 5
}
```

**OpenSearch document:**

```json
{
  "@timestamp": "2025-10-13T12:15:30.000Z",
  "message": "0/3 nodes are available: 3 Insufficient cpu.",
  "event": {
    "type": "Warning",
    "reason": "FailedScheduling",
    "category": "scheduling",
    "count": 5
  },
  "kubernetes": {
    "namespace": "prod",
    "resource_kind": "Pod",
    "name": "nginx-7",
    "uid": "pod-uid-5678",
    "event_name": "nginx-7.abcd1234"
  },
  "collector": {
    "name": "k8s-events-collector",
    "type": "watcher"
  },
  "raw": "{...full event...}"
}
```

---

## OpenSearch Integration

### Bulk API Usage

OpenSearch uses **newline-delimited JSON (NDJSON)** for bulk operations:

```http
POST /logs-kube-audit-2025.10.13/_bulk
Content-Type: application/x-ndjson

{ "index": { "_id": "a1b2c3d4-e5f6-7890" } }
{ "@timestamp":"2025-10-13T12:05:21.234Z", "event.action":"create", "kubernetes":{"namespace":"prod","resource":"pods","name":"nginx-7"}, "user":{"name":"alice"} }
{ "index": {} }
{ "@timestamp":"2025-10-13T12:10:00.000Z", "snapshot.type":"networkpolicy", "kubernetes":{"namespace":"prod","name":"deny-all-ingress"} }
```

**Key points:**
- Use `_id` for idempotency (prevents duplicates on retry)
- Recommended `_id` sources:
  - Audit logs: `audit.id`
  - Snapshots: `snapshot.id`
  - Application logs: `trace.id` + timestamp
- Batch size: 500-1000 documents or 5MB per request

---

### Index Mapping Template

**Critical mapping decisions:**

```json
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "refresh_interval": "5s",
      "codec": "best_compression"
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date",
          "format": "strict_date_optional_time||epoch_millis"
        },
        "message": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "service.name": { "type": "keyword" },
        "log.level": { "type": "keyword" },
        "host.name": { "type": "keyword" },
        "host.ip": { "type": "ip" },
        "kubernetes.namespace": { "type": "keyword" },
        "kubernetes.pod.name": { "type": "keyword" },
        "kubernetes.pod.uid": { "type": "keyword" },
        "kubernetes.container.name": { "type": "keyword" },
        "kubernetes.node": { "type": "keyword" },
        "kubernetes.resource_kind": { "type": "keyword" },
        "kubernetes.spec": {
          "type": "object",
          "enabled": false
        },
        "event.action": { "type": "keyword" },
        "event.category": { "type": "keyword" },
        "event.outcome": { "type": "keyword" },
        "user.name": { "type": "keyword" },
        "user.uid": { "type": "keyword" },
        "source.ip": { "type": "ip" },
        "audit.id": { "type": "keyword" },
        "snapshot.type": { "type": "keyword" },
        "snapshot.id": { "type": "keyword" },
        "raw": {
          "type": "text",
          "index": false
        }
      }
    }
  }
}
```

**Mapping strategy:**
- `keyword` for aggregations and exact-match filters
- `text` for full-text search with `keyword` subfield
- `object` with `enabled: false` for large nested objects (saves space, no querying)
- `nested` type only when querying inside arrays of objects
- `index: false` for `raw` field (store but don't index)

---

### Index Lifecycle Management (ILM)

**Example policy:**

```json
{
  "policy": {
    "description": "Hot-warm-cold-delete policy for logs",
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_size": "50gb",
            "max_docs": 100000000
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "replica_count": {
            "number_of_replicas": 0
          },
          "force_merge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

**Per-source retention policies:**

| Log Source | Hot | Warm | Cold | Delete | Rationale |
|------------|-----|------|------|--------|-----------|
| Container logs | 7d | 23d | - | 30d | Short-term debugging |
| Kubelet/System | 7d | 23d | - | 30d | Operational troubleshooting |
| Audit logs | 14d | 76d | 275d | 365d | Compliance requirement |
| Security events | 14d | 76d | 275d | 365d | Forensics |
| K8s snapshots | 30d | 60d | - | 90d | State history |

---

## Index Strategy

### Option A: Per-Source Indices (Recommended)

**Index pattern:**
- `logs-containers-YYYY.MM.DD`
- `logs-kubelet-YYYY.MM.DD`
- `logs-audit-YYYY.MM.DD`
- `logs-syslog-YYYY.MM.DD`
- `k8s-snapshots-YYYY.MM.DD`
- `k8s-events-YYYY.MM.DD`

**Advantages:**
✅ Different ILM policies per source  
✅ Optimized mappings per log type  
✅ Better query performance (smaller indices)  
✅ RBAC per index  
✅ Independent scaling  
✅ Clear data lifecycle management  

**Disadvantages:**
❌ Requires aliases for cross-index queries  
❌ More index templates to manage  

**Implementation:**

```json
{
  "aliases": {
    "logs-all": {},
    "logs-k8s": {}
  }
}
```

Query across all: `GET /logs-all/_search`  
Query K8s only: `GET /logs-k8s/_search`

---

### Option B: Unified Index (Not Recommended for Production)

**Index pattern:** `logs-YYYY.MM.DD`

**Advantages:**
✅ Simple queries  
✅ Single mapping  

**Disadvantages:**
❌ Single ILM policy for all sources  
❌ Mapping explosion (too many fields)  
❌ Poor query performance  
❌ No granular RBAC  
❌ Difficult to optimize  

**Verdict:** Use per-source indices for production environments.

---

## Custom Collector Implementation

### Architecture

```
┌─────────────────┐
│  K8s API Server │
└────────┬────────┘
         │ Watch/List
         ↓
┌─────────────────────┐
│ State Collector Pod │
│  (Deployment 2x)    │
└────────┬────────────┘
         │ Bulk API
         ↓
┌─────────────────────┐
│   OpenSearch        │
└─────────────────────┘
```

### Python Implementation Example

```python
#!/usr/bin/env python3
"""
Kubernetes State Collector for OpenSearch
Collects NetworkPolicies, Roles, Events, and other resources
"""

import json
import time
import logging
from datetime import datetime, timezone
from typing import Dict, List, Any

import requests
from kubernetes import client, config, watch
from requests.auth import HTTPBasicAuth

# Configuration
OPENSEARCH_URL = "https://opensearch.logging.svc:9200"
OPENSEARCH_USER = "admin"
OPENSEARCH_PASSWORD = "secure_password"
COLLECTION_INTERVAL = 300  # 5 minutes
COLLECTOR_VERSION = "1.0.0"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class K8sStateCollector:
    def __init__(self):
        # Load K8s config (in-cluster)
        config.load_incluster_config()
        self.core_v1 = client.CoreV1Api()
        self.net_v1 = client.NetworkingV1Api