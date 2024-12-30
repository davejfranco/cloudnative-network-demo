output "public_ip" {
  value = aws_instance.routers[*].public_ip
}

output "ssh_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
