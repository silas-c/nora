terraform {
  required_version = ">= 1.5, < 2.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.2"
    }
  }
}

provider "docker" {}

resource "docker_image" "demo" {
  name         = "nginx:stable-alpine"
  keep_locally = true
}

resource "docker_container" "demo" {
  name        = "nora-action-demo"
  image       = docker_image.demo.image_id
  memory      = 128
  memory_swap = 256

  ports {
    internal = 80
    external = 8787
    ip       = "127.0.0.1"
  }

  dynamic "upload" {
    for_each = fileset("${path.module}/site", "*.html")
    content {
      content = file("${path.module}/site/${upload.value}")
      file    = "/usr/share/nginx/html/${upload.value}"
    }
  }
}

output "demo_url" {
  value = "http://127.0.0.1:8787"
}
