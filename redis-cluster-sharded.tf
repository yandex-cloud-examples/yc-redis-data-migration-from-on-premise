# Infrastructure for sharded Yandex Managed Service for Valkey™ cluster and Virtual Machine in Yandex Compute Cloud
#
# RU: https://cloud.yandex.ru/docs/managed-valkey/tutorials/valkey-as-php-sessions-storage
# EN: https://cloud.yandex.com/en/docs/managed-valkey/tutorials/valkey-as-php-sessions-storage
#
# Specify the following settings:
locals {
  # The following settings are to be specified by the user. Change them as you wish.

  # Settings for the Managed Service for Valkey™ cluster
  password    = "" # Password for the Managed Service for Valkey™ cluster
  shard_name1 = "" # Name of the first shard of the Managed Service for Valkey™ cluster
  shard_name2 = "" # Name of the second shard of the Managed Service for Valkey™ cluster
  shard_name3 = "" # Name of the third shard of the Managed Service for Valkey™ cluster

  # (Optional) Settings for the VM in Compute Cloud. Uncomment these lines if you use a VM to connect to the cluster.
  # vm_image_id   = "" # Public image ID for the VM. See: https://cloud.yandex.com/en/docs/compute/operations/images-with-pre-installed-software/get-list.
  # vm_username   = "" # Username for the VM. Ubuntu images use the `ubuntu` username by default.
  # vm_public_key = "" # Full path to the SSH public key for the VM

  # The following settings are predefined. Change them only if necessary.

  # Settings for the Network infrastructure
  zone_a_v4_cidr_blocks = "10.1.0.0/16" # CIDR block for the subnet in the ru-central1-a availability zone
  zone_b_v4_cidr_blocks = "10.2.0.0/16" # CIDR block for the subnet in the ru-central1-b availability zone
  zone_d_v4_cidr_blocks = "10.3.0.0/16" # CIDR block for the subnet in the ru-central1-d availability zone

  # Settings for the Managed Service for Valkey™ cluster
  redis_version = "7.2-valkey" # Version of the Managed Service for Valkey™
}

resource "yandex_vpc_network" "network" {
  description = "Network for the Managed Service for Valkey cluster and VM"
  name        = "network"
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = "subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_subnet" "subnet-b" {
  description    = "Subnet in the ru-central1-b availability zone"
  name           = "subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [local.zone_b_v4_cidr_blocks]
}

resource "yandex_vpc_subnet" "subnet-d" {
  description    = "Subnet in the ru-central1-d availability zone"
  name           = "subnet-d"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [local.zone_d_v4_cidr_blocks]
}

resource "yandex_vpc_security_group" "security-group-redis" {
  description = "Security group for the Managed Service for Valkey cluster"
  network_id  = yandex_vpc_network.network.id

  # Required for clusters created with TLS
  ingress {
    description    = "Allow direct connections to the master with SSL"
    protocol       = "TCP"
    port           = 6380
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Required for clusters created without TLS
  #ingress {
  #  description    = "Allow direct connections to the master without SSL"
  #  protocol       = "TCP"
  #  port           = 6379
  #  v4_cidr_blocks = ["0.0.0.0/0"]
  #}

  ingress {
    protocol       = "TCP"
    description    = "Allow connections to the Redis Sentinel"
    port           = 26379
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# If you use VM for connection to the cluster, uncomment these lines.
#resource "yandex_vpc_security_group" "security-group-vm" {
#  description = "Security group for the VM"
#  network_id  = yandex_vpc_network.network.id
#
#  ingress {
#    description    = "Allow SSH connections for VM from the Internet"
#    protocol       = "TCP"
#    port           = 22
#    v4_cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  egress {
#    description    = "Allow outgoing connections to any required resource"
#    protocol       = "ANY"
#    from_port      = 0
#    to_port        = 65535
#    v4_cidr_blocks = ["0.0.0.0/0"]
#  }
#}

resource "yandex_mdb_redis_cluster_v2" "redis-cluster" {
  description        = "Managed Service for Valkey cluster"
  name               = "valkey-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.security-group-redis.id]
  sharded            = true
  tls_enabled        = true # TLS support mode. Must be enabled for public access to the cluster host. For a method without VM.

  config = {
    password = local.password
    version  = local.redis_version
  }

  resources = {
    resource_preset_id = "hm2.nano" # 2 vCPU, 8 GB RAM
    disk_type_id       = "network-ssd"
    disk_size          = 16 # GB
  }

  hosts = {
    host1 = {
      zone             = "ru-central1-a"
      subnet_id        = yandex_vpc_subnet.subnet-a.id
      shard_name       = local.shard_name1
      assign_public_ip = true # Required for connection from the Internet. For a method without VM.
    }

    host2 = {
      zone             = "ru-central1-b"
      subnet_id        = yandex_vpc_subnet.subnet-b.id
      shard_name       = local.shard_name2
      assign_public_ip = true # Required for connection from the Internet. For a method without VM.
    }

    host3 = {
      zone             = "ru-central1-d"
      subnet_id        = yandex_vpc_subnet.subnet-d.id
      shard_name       = local.shard_name3
      assign_public_ip = true # Required for connection from the Internet. For a method without VM.
    }
  }
}

# If you use VM for connection to the cluster, uncomment these lines.
#resource "yandex_compute_instance" "vm-linux" {
#  description = "Virtual Machine in Yandex Compute Cloud"
#  name        = "vm-linux"
#  platform_id = "standard-v3" # Intel Ice Lake
#
#  resources {
#    cores  = 2
#    memory = 2 # GB
#  }
#
#  boot_disk {
#    initialize_params {
#      image_id = local.vm_image_id
#    }
#  }
#
#  network_interface {
#    subnet_id = yandex_vpc_subnet.subnet-a.id
#    nat       = true # Required for connection from the Internet.
#
#    security_group_ids = [
#      yandex_vpc_security_group.security-group-redis.id,
#      yandex_vpc_security_group.security-group-vm.id
#    ]
#  }
#
#  metadata = {
#    ssh-keys = "${local.vm_username}:${file(local.vm_public_key)}" # Username and SSH public key full path.
#  }
#}
