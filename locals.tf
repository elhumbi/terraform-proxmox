locals {
  # Feste MAC-Adressen für Controller
  controller_macs = {
    controller1 = "02:00:00:01:00:01" # → 192.168.1.121
    controller2 = "02:00:00:01:00:02" # → 192.168.1.122
    controller3 = "02:00:00:01:00:03" # → 192.168.1.123
  }

  # Feste MAC-Adressen für Worker
  worker_macs = {
    worker1 = "02:00:00:02:00:01" # → 192.168.1.127
    worker2 = "02:00:00:02:00:02" # → 192.168.1.128
    worker3 = "02:00:00:02:00:03" # → 192.168.1.129
  }

  # IP-Zuordnungen basierend auf DHCP-Reservierung
  controller_ip_map = {
    controller1 = "192.168.1.121"
    controller2 = "192.168.1.122"
    controller3 = "192.168.1.123"
  }

  worker_ip_map = {
    worker1 = "192.168.1.127"
    worker2 = "192.168.1.128"
    worker3 = "192.168.1.129"
  }

  # Listen der IP-Adressen
  controller_ips = [
    "192.168.1.121",
    "192.168.1.122",
    "192.168.1.123"
  ]

  worker_ips = [
    "192.168.1.127",
    "192.168.1.128",
    "192.168.1.129"
  ]

  # Cluster VIP (erste Controller IP als Fallback)
  cluster_vip = "192.168.1.121"

  # VM-IDs für Proxmox VMs
  vm_ids = {
    controller1 = 121
    controller2 = 122
    controller3 = 123
    worker1     = 127
    worker2     = 128
    worker3     = 129
  }

  # Node-Verteilung auf Proxmox-Nodes (Round-Robin)
  node_distribution = {
    controller1 = "pve01"
    controller2 = "pve02"
    controller3 = "pve01"
    worker1     = "pve02"
    worker2     = "pve01"
    worker3     = "pve02"
  }

  # Alle Nodes zusammengefasst
  all_nodes = merge(local.controller_macs, local.worker_macs)

  # Alle IPs zusammengefasst
  all_ips = merge(local.controller_ip_map, local.worker_ip_map)
}