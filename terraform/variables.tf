variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "key_pair_name" {
  type    = string
  default = "platform-lab-key"
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/lbkey.pem.pub" # The .pub file, not the .pem
}
