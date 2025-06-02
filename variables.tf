# Proxmox Configuration
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.1.115:8006/"
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for Proxmox"
  type        = bool
  default     = true
}

variable "primary_node" {
  description = "Primary Proxmox node for ISO downloads"
  type        = string
  default     = "pve01"
}

variable "storage_name" {
  description = "Proxmox storage name for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "iso_storage_name" {
  description = "Proxmox storage name for ISO files (must be file-based)"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "talos-cluster"
}

variable "talos_version" {
  description = "Talos version"
  type        = string
  default     = "v1.10.2"
}

# Controller Node Configuration
variable "controller_cpu_cores" {
  description = "Number of CPU cores for controller nodes"
  type        = number
  default     = 2
}

variable "controller_memory" {
  description = "Memory in MB for controller nodes"
  type        = number
  default     = 4096
}

variable "controller_disk_size" {
  description = "Disk size in GB for controller nodes"
  type        = number
  default     = 32
}

# Worker Node Configuration
variable "worker_cpu_cores" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 4096
}

variable "worker_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 64
}

# Network Configuration
variable "metallb_ip_range" {
  description = "IP range for MetalLB load balancer"
  type        = string
  default     = "192.168.1.180-192.168.1.190"
}

# Helm Chart Versions (Latest as of May 2025)
variable "cilium_version" {
  description = "Cilium CNI version"
  type        = string
  default     = "1.16.5"
}

variable "metallb_version" {
  description = "MetalLB version"
  type        = string
  default     = "0.14.8"
}

variable "cert_manager_version" {
  description = "Cert-Manager version"
  type        = string
  default     = "v1.17.2"
}

variable "opentelemetry_version" {
  description = "OpenTelemetry Operator version"
  type        = string
  default     = "0.73.0"
}

variable "k8s_dashboard_version" {
  description = "Kubernetes Dashboard version"
  type        = string
  default     = "7.10.0"
}

variable "argocd_version" {
  description = "ArgoCD version"
  type        = string
  default     = "8.0.9"
}