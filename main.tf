variable "do_token" {
  type = string
}

variable "cluster_name" {
  type = string
  default = "brains"
}

variable "cluster_region" {
  type = string
  default = "lon1"
}

variable "node_pool_name" {
  type = string
  default = "worker_pool"
}

variable "node_pool_size" {
  type = string
  default = "s-1vcpu-2gb" # 1vcpu 3gb ram
}

variable "node_count_min" {
  type = number
  default = 1
}

variable "node_count_max" {
  type = number
  default = 1
}

variable "container_registry_name" {
  type = string
  default = "registry"
}

terraform {
  backend "local" {
    path = "../.backend"
  }
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "2.21.0"
    }
#    kubernetes {
#      version = "~> 1.11"
#    }
#    kubectl {}
#    helm {
#      version = "~> 1.2"
#    }
    kubectl = {
      source  = "gavinbunney/kubectl"
#      version = ">= 1.7.0"
    }
  }
}

provider "digitalocean" {
  token   = var.do_token
}

provider "kubernetes" {
#  load_config_file = false
  host  = digitalocean_kubernetes_cluster.cluster.endpoint
  token = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
  )
}

provider "kubectl" {
  load_config_file = false
  host  = digitalocean_kubernetes_cluster.cluster.endpoint
  token = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
  )
  apply_retry_count = 5
}

provider "helm" {
  kubernetes {
    host  = digitalocean_kubernetes_cluster.cluster.endpoint
    token = digitalocean_kubernetes_cluster.cluster.kube_config[0].token

    cluster_ca_certificate = base64decode(
      digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
    )
  }
}

resource "digitalocean_kubernetes_cluster" "cluster" {
  name    = var.cluster_name
  region  = var.cluster_region
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = "1.22.8-do.1"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 1
  }
}

#resource "digitalocean_kubernetes_node_pool" "node-pool" {
#  cluster_id = digitalocean_kubernetes_cluster.cluster.id
#
#  name       = var.node_pool_name
#  size       = var.node_pool_size
#  node_count = var.node_count_min
#  auto_scale = true
#  min_nodes  = var.node_count_min
#  max_nodes  = var.node_count_max
#
#}

# Create a new container registry
#resource "digitalocean_container_registry" "registry" {
#  name = var.container_registry_name
#  subscription_tier_slug = "starter"
#}


#resource "helm_release" "metrics-server" {
#  name  = "metrics-server"
#
#  repository = "https://kubernetes-charts.storage.googleapis.com"
#  chart = "metrics-server"
#  namespace = "kube-system"
#
#  values = [
#    "${file("metrics-server-values.yaml")}"
#  ]
#}
#
resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress-nginx" {
  name  = "ingress-nginx"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart = "ingress-nginx"
  namespace = "ingress-nginx"

#  timeout    = 800

  depends_on = [ kubernetes_namespace.ingress ]
}
#
resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert-manager" {
  name  = "cert-manager"

  repository = "https://charts.jetstack.io"
  chart = "cert-manager"
  namespace = "cert-manager"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [ kubernetes_namespace.cert-manager ]
}

resource "kubectl_manifest" "letsencrypt-issuer" {
  yaml_body = file("${path.module}/letsencrypt-issuer.yaml")
  depends_on = [ helm_release.cert-manager ]
}

#output "container_registry" {
#  value = "${digitalocean_container_registry.registry.endpoint}"
#}

