variable "state_passphrase" {
  description = "State encryption passphrase from secrets/opentofu.sops.yml, loaded by scripts/tofu.sh."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "Use a random state passphrase of at least 32 characters."
  }
}
terraform {
  encryption {
    key_provider "pbkdf2" "offline" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.offline
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}
