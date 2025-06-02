# Talos Kubernetes Cluster on Proxmox

This Terraform configuration deploys a production-ready Talos Linux-based Kubernetes cluster on Proxmox VE with a complete set of essential services.

## Architecture

- **3 Controller Nodes**: High availability Kubernetes control plane
- **3 Worker Nodes**: Kubernetes workload nodes
- **Load Balancing**: MetalLB for LoadBalancer services
- **Networking**: Cilium CNI with Hubble observability
- **TLS**: cert-manager with internal CA for service certificates
- **GitOps**: ArgoCD for application deployment
- **Monitoring**: Kubernetes Dashboard for cluster management

## Prerequisites

### Infrastructure Requirements
- Proxmox VE cluster with at least 2 nodes (`pve01`, `pve02`)
- Sufficient resources:
  - **CPU**: 12 cores total (2 per node)
  - **Memory**: 24GB total (4GB per node)
  - **Storage**: 288GB total (32GB controllers + 64GB workers)
- Network bridge `vmbr0` configured
- DHCP server with MAC address reservations (see Network Configuration)

### Software Requirements
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Talos CLI](https://www.talos.dev/v1.10/introduction/getting-started/#talosctl) >= 1.10.2
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management

### Required Files
- Talos ISO: `talos-v1.10.2-extensions.iso` uploaded to Proxmox local storage
  - Download from: https://factory.talos.dev/
  - Upload to Proxmox: `Datacenter → Storage → local → ISO Images`

## Network Configuration

The configuration uses static MAC addresses with DHCP reservations:

### Controller Nodes
| Node | MAC Address | Reserved IP | VM ID |
|------|-------------|-------------|-------|
| controller1 | `02:00:00:01:00:01` | `192.168.1.121` | 121 |
| controller2 | `02:00:00:01:00:02` | `192.168.1.122` | 122 |
| controller3 | `02:00:00:01:00:03` | `192.168.1.123` | 123 |

### Worker Nodes
| Node | MAC Address | Reserved IP | VM ID |
|------|-------------|-------------|-------|
| worker1 | `02:00:00:02:00:01` | `192.168.1.127` | 127 |
| worker2 | `02:00:00:02:00:02` | `192.168.1.128` | 128 |
| worker3 | `02:00:00:02:00:03` | `192.168.1.129` | 129 |

### Load Balancer Pool
- **MetalLB Range**: `192.168.1.180-192.168.1.190`

## Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo>
cd terraform-proxmox
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your Proxmox credentials:
```hcl
proxmox_password = "your-proxmox-password"
```

### 3. Configure DHCP Reservations
Add the MAC/IP mappings from the table above to your DHCP server.

### 4. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Deploy cluster
terraform apply
```

### 5. Access Your Cluster
```bash
# Set KUBECONFIG
terraform output -raw kubeconfig > ~/.kube/config
export KUBECONFIG=$(pwd)/kubeconfig
source ~/.bashrc

# Verify cluster
kubectl get nodes

# Get LoadBalancer IP for services
kubectl get svc cilium-ingress -n kube-system
```

## File Structure

```
.
├── main.tf                 # Main Terraform configuration
├── variables.tf           # Variable definitions
├── locals.tf             # Local values and mappings
├── terraform.tfvars.example # Example variables file
├── kubeconfig            # Generated after deployment
└── README.md
```

## Deployed Services

### Core Infrastructure
- **Talos Linux**: Immutable OS designed for Kubernetes
- **Cilium**: Advanced CNI with eBPF-based networking
- **MetalLB**: Bare-metal load balancer
- **cert-manager**: Certificate management with internal CA

### Management & GitOps
- **Kubernetes Dashboard**: Web-based cluster UI
- **ArgoCD**: GitOps continuous deployment
- **Hubble UI**: Network observability dashboard

### Service Access

After deployment, add these entries to your `/etc/hosts` file:
```
<INGRESS-IP>  argocd.home.local
<INGRESS-IP>  dashboard.home.local
<INGRESS-IP>  hubble.home.local
```

Get the Ingress IP:
```bash
kubectl get svc cilium-ingress -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Default Credentials

**Kubernetes Dashboard**: Skip authentication (enabled)
**ArgoCD**: 
```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Configuration Options

### VM Resources
Adjust in `terraform.tfvars`:
```hcl
# Controller nodes
controller_cpu_cores = 2
controller_memory    = 4096  # MB
controller_disk_size = 32    # GB

# Worker nodes  
worker_cpu_cores = 4
worker_memory    = 8192      # MB
worker_disk_size = 100       # GB
```

### Network Settings
```hcl
network_bridge      = "vmbr0"
metallb_ip_range   = "192.168.1.180-192.168.1.190"
```

### Software Versions
All versions are pinned and can be updated in `variables.tf`:
```hcl
talos_version        = "v1.10.2"
cilium_version       = "1.16.5"
metallb_version      = "0.14.8"
cert_manager_version = "v1.17.2"
argocd_version       = "8.0.9"
```

## Advanced Usage

### Talos Management
```bash
# Configure talosctl
terraform output -raw talos_config > ~/.talos/config

# Check cluster health
talosctl health --nodes <controller-ip>

# Get cluster info
talosctl cluster show
```

### Certificate Management
```bash
# Get internal CA certificate for browser import
kubectl get secret internal-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > internal-ca.crt

openssl x509 -in ~/internal-ca.crt -text -noout

# In Keychain importieren for MACOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/internal-ca.crt

```

### Troubleshooting
```bash
# Check node status
kubectl get nodes -o wide

# Check pod status across namespaces
kubectl get pods --all-namespaces

# Check Cilium connectivity
kubectl exec -n kube-system ds/cilium -- cilium status

# Check MetalLB configuration
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

## Maintenance

### Updating Talos
1. Update `talos_version` in `variables.tf`
2. Upload new Talos ISO to Proxmox
3. Update `talos_iso_id` in `locals.tf`
4. Run `terraform apply`

### Scaling
To add more worker nodes:
1. Add entries to `worker_macs` and `worker_ip_map` in `locals.tf`
2. Configure DHCP reservations
3. Run `terraform apply`

## Security Considerations

- **Network Isolation**: Configure Proxmox firewall rules as needed
- **RBAC**: Review and customize Kubernetes RBAC policies
- **Certificates**: Internal CA is self-signed; consider external CA for production
- **Secrets**: Use Terraform Cloud or similar for sensitive variables
- **Updates**: Regularly update Talos and Kubernetes versions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[MIT License](LICENSE)

## Support

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Proxmox Documentation](https://pve.proxmox.com/pve-docs/)

---

**⚠️ Important**: This configuration is designed for homelab/development use. For production deployments, review security settings, resource allocations, and backup strategies. This is a homeproject for testing terraform... and I want give a garanty if it works on your homelab