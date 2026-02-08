output "server_public_ip" {
  description = "외부에서 접속할 K3s Server IP"
  value       = aws_instance.k3s_server.public_ip
}

output "agent_private_ips" {
  description = "내부에서 확인 가능한 K3s Agent IP 목록"
  value       = aws_instance.k3s_agent[*].private_ip
}
