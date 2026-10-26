output "instance_ips" {
  description = "Public and private IPs for each instance"
  value = {
    for name, inst in aws_instance.lab : name => {
      public_ip  = inst.public_ip
      private_ip = inst.private_ip
    }
  }
}

output "lb_public_ip" {
  value = aws_instance.lab["lb"].public_ip
}
