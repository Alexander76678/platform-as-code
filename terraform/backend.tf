# backend.tf
terraform {
  backend "s3" {
    bucket       = "salim-platform-terraform-state-2026"
    key          = "platform-as-code/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
