terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.43"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Proxmox Provider Configuration
provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = var.proxmox_tls_insecure
}

# Talos Provider Configuration
provider "talos" {}

# Generate Talos machine secrets
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Generate Talos client configuration
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controller_ips
}

# Generate Talos machine configurations for controllers
data "talos_machine_configuration" "controller" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${local.cluster_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
      }
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            dhcp      = true
          }]
        }
        install = {
          disk       = "/dev/sda"
          image      = "factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:${var.talos_version}"
          bootloader = true
          wipe       = false
        }
        kubelet = {
          extraArgs = {
            rotate-server-certificates = "true"
          }
        }
      }
    })
  ]
}

# Generate Talos machine configurations for workers
data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${local.cluster_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            dhcp      = true
          }]
        }
        install = {
          disk       = "/dev/sda"
          image      = "factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:${var.talos_version}"
          bootloader = true
          wipe       = false
        }
        kubelet = {
          extraArgs = {
            rotate-server-certificates = "true"
          }
        }
      }
    })
  ]
}

# Use existing Talos ISO (manually downloaded)
locals {
  talos_iso_id = "local:iso/talos-v1.10.2-extensions.iso"
}

# Create Proxmox VMs for Controllers
resource "proxmox_virtual_environment_vm" "controller" {
  for_each = local.controller_macs

  name        = each.key
  description = "Talos Controller ${each.key}"
  node_name   = local.node_distribution[each.key]
  vm_id       = local.vm_ids[each.key]

  cpu {
    cores = var.controller_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.controller_memory
  }

  network_device {
    bridge      = var.network_bridge
    mac_address = each.value
  }

  # Primary disk for installation
  disk {
    datastore_id = var.storage_name
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    size         = var.controller_disk_size
  }

  # CD-ROM for ISO boot
  cdrom {
    file_id   = local.talos_iso_id
    interface = "ide0"
  }

  boot_order = ["ide0", "scsi0"]

  started = true
}

# Create Proxmox VMs for Workers
resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.worker_macs

  name        = each.key
  description = "Talos Worker ${each.key}"
  node_name   = local.node_distribution[each.key]
  vm_id       = local.vm_ids[each.key]

  cpu {
    cores = var.worker_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_memory
  }

  network_device {
    bridge      = var.network_bridge
    mac_address = each.value
  }

  # Primary disk for installation
  disk {
    datastore_id = var.storage_name
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    size         = var.worker_disk_size
  }

  # CD-ROM for ISO boot
  cdrom {
    file_id   = local.talos_iso_id
    interface = "ide0"
  }

  boot_order = ["ide0", "scsi0"]

  started = true
}

# Apply Talos configuration to controllers
resource "talos_machine_configuration_apply" "controller" {
  for_each = local.controller_macs

  depends_on = [proxmox_virtual_environment_vm.controller]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration
  node                        = local.controller_ip_map[each.key]
  endpoint                    = local.controller_ip_map[each.key]
}

# Apply Talos configuration to workers
resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_macs

  depends_on = [proxmox_virtual_environment_vm.worker]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_ip_map[each.key]
  endpoint                    = local.worker_ip_map[each.key]
}

# Bootstrap Talos cluster
resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.controller,
    talos_machine_configuration_apply.worker
  ]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.controller_ips[0]
  endpoint             = local.controller_ips[0]
}

# Get kubeconfig
data "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.controller_ips[0]
  endpoint             = local.controller_ips[0]
}

# Save kubeconfig to file
resource "local_file" "kubeconfig" {
  depends_on = [data.talos_cluster_kubeconfig.this]
  content    = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  filename   = "${path.module}/kubeconfig"
}

# Configure Kubernetes and Helm providers
provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  kubernetes {
    config_path = local_file.kubeconfig.filename
  }
}

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}

# Install Cilium CNI
resource "helm_release" "cilium" {
  depends_on = [talos_machine_bootstrap.this]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = var.cilium_version

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  set {
    name  = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }

  set {
    name  = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }

  set {
    name  = "cgroup.autoMount.enabled"
    value = "false"
  }

  set {
    name  = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }

  set {
    name  = "k8sServiceHost"
    value = local.cluster_vip
  }

  set {
    name  = "k8sServicePort"
    value = "6443"
  }

  # Enable Hubble for observability
  set {
    name  = "hubble.enabled"
    value = "true"
  }

  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }

  set {
    name  = "hubble.ui.enabled"
    value = "true"
  }

  # Enable Cilium Ingress Controller
  set {
    name  = "ingressController.enabled"
    value = "true"
  }

  set {
    name  = "ingressController.loadbalancerMode"
    value = "shared"
  }

  set {
    name  = "ingressController.service.type"
    value = "LoadBalancer"
  }
}

# Create Hubble UI Ingress
resource "kubectl_manifest" "hubble_ui_ingress" {
  depends_on = [helm_release.cilium, kubectl_manifest.internal_ca_issuer]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "hubble-ui-ingress"
      namespace = "kube-system"
      annotations = {
        "cert-manager.io/cluster-issuer" = "internal-ca-issuer"
        "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
      }
    }
    spec = {
      ingressClassName = "cilium"
      tls = [
        {
          hosts = ["hubble.home.local"]
          secretName = "hubble-ui-tls"
        }
      ]
      rules = [
        {
          host = "hubble.home.local"
          http = {
            paths = [
              {
                path = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "hubble-ui"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })
}

# Create MetalLB namespace with privileged security policy
resource "kubernetes_namespace" "metallb_system" {
  depends_on = [helm_release.cilium]

  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# Install MetalLB
resource "helm_release" "metallb" {
  depends_on = [kubernetes_namespace.metallb_system]

  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = "metallb-system"
  version    = var.metallb_version

  create_namespace = false
  timeout          = 600

  values = [
    yamlencode({
      controller = {
        image = {
          repository = "quay.io/metallb/controller"
          tag        = "v${var.metallb_version}"
        }
      }
      speaker = {
        image = {
          repository = "quay.io/metallb/speaker"
          tag        = "v${var.metallb_version}"
        }
        tolerations = [
          {
            effect = "NoSchedule"
            key    = "node-role.kubernetes.io/control-plane"
          }
        ]
      }
    })
  ]
}

# Configure MetalLB IP Pool
resource "kubectl_manifest" "metallb_ippool" {
  depends_on = [helm_release.metallb]

  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "main-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_ip_range]
    }
  })
}

# Configure MetalLB L2Advertisement
resource "kubectl_manifest" "metallb_l2advertisement" {
  depends_on = [kubectl_manifest.metallb_ippool]

  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "main-advertisement"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["main-pool"]
    }
  })
}

# Install Cert-Manager
resource "helm_release" "cert_manager" {
  depends_on = [helm_release.metallb]

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = var.cert_manager_version

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }
}

# Create self-signed ClusterIssuer for internal CA
resource "kubectl_manifest" "selfsigned_issuer" {
  depends_on = [helm_release.cert_manager]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned-issuer"
    }
    spec = {
      selfSigned = {}
    }
  })
}

# Create internal CA certificate
resource "kubectl_manifest" "internal_ca_cert" {
  depends_on = [kubectl_manifest.selfsigned_issuer]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "internal-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA = true
      commonName = "home.local Internal CA"
      secretName = "internal-ca-secret"
      duration = "8760h" # 1 year
      renewBefore = "720h" # 30 days
      subject = {
        countries = ["CH"]
        localities = ["Wuerenlos"]
        organizationalUnits = ["IT Department"]
        organizations = ["home.local"]
      }
      issuerRef = {
        name = "selfsigned-issuer"
        kind = "ClusterIssuer"
      }
    }
  })
}

# Create internal CA ClusterIssuer
resource "kubectl_manifest" "internal_ca_issuer" {
  depends_on = [kubectl_manifest.internal_ca_cert]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "internal-ca-issuer"
    }
    spec = {
      ca = {
        secretName = "internal-ca-secret"
      }
    }
  })
}

# Install Kubernetes Dashboard
resource "helm_release" "kubernetes_dashboard" {
  depends_on = [kubectl_manifest.internal_ca_issuer]

  name       = "kubernetes-dashboard"
  repository = "https://kubernetes.github.io/dashboard/"
  chart      = "kubernetes-dashboard"
  namespace  = "kubernetes-dashboard"
  version    = var.k8s_dashboard_version

  create_namespace = true

  values = [
    yamlencode({
      service = {
        type = "ClusterIP"  # Use Ingress instead of LoadBalancer
      }
      extraArgs = [
        "--enable-skip-login",
        "--disable-settings-authorizer"
      ]
      rbac = {
        clusterReadOnlyRole = true
      }
      ingress = {
        enabled = true
        className = "cilium"
        hosts = [
          {
            host = "dashboard.home.local"
            paths = [
              {
                path = "/"
                pathType = "Prefix"
              }
            ]
          }
        ]
        tls = [
          {
            secretName = "dashboard-tls"
            hosts = ["dashboard.home.local"]
          }
        ]
        annotations = {
          "cert-manager.io/cluster-issuer" = "internal-ca-issuer"
          "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
          "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
        }
      }
    })
  ]
}

# Create admin user for dashboard
resource "kubectl_manifest" "dashboard_admin_user" {
  depends_on = [helm_release.kubernetes_dashboard]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "admin-user"
      namespace = "kubernetes-dashboard"
    }
  })
}

# Create cluster role binding for admin user
resource "kubectl_manifest" "dashboard_admin_binding" {
  depends_on = [kubectl_manifest.dashboard_admin_user]

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "admin-user"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "cluster-admin"
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = "admin-user"
      namespace = "kubernetes-dashboard"
    }]
  })
}

# Install ArgoCD
resource "helm_release" "argocd" {
  depends_on = [kubectl_manifest.internal_ca_issuer]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = var.argocd_version

  create_namespace = true

  values = [
    yamlencode({
      global = {
        domain = "argocd.home.local"
      }
      server = {
        service = {
          type = "ClusterIP"  # Back to ClusterIP for Ingress
        }
        extraArgs = [
          "--insecure"
        ]
        ingress = {
          enabled = true
          ingressClassName = "cilium"
          hostname = "argocd.home.local"
          annotations = {
            "cert-manager.io/cluster-issuer" = "internal-ca-issuer"
            "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
          }
          tls = true
        }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      controller = {
        metrics = {
          enabled = true
        }
      }
      repoServer = {
        metrics = {
          enabled = true
        }
      }
    })
  ]
}

# Output important information
output "talos_config" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes configuration"
  value       = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = "https://${local.cluster_vip}:6443"
}

output "controller_ips" {
  description = "Controller node IP addresses"
  value       = local.controller_ips
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value       = local.worker_ips
}

# Output for internal CA certificate (to import into browsers/systems)
output "internal_ca_certificate" {
  description = "Internal CA certificate for importing into browsers"
  value       = "kubectl get secret internal-ca-secret -n cert-manager -o jsonpath='{.data.ca\\.crt}' | base64 -d"
  sensitive   = false
}

output "ingress_ip" {
  description = "Cilium Ingress LoadBalancer IP"
  value       = "kubectl get svc cilium-ingress -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "dns_entries" {
  description = "DNS entries for /etc/hosts"
  value = <<-EOF
# Add these entries to your /etc/hosts file:
# <INGRESS-IP>  argocd.home.local
# <INGRESS-IP>  dashboard.home.local  
# <INGRESS-IP>  hubble.home.local

# To get the Ingress IP run:
kubectl get svc cilium-ingress -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
EOF
}