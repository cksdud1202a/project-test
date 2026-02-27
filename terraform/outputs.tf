output "server_public_ip" {
  description = "외부에서 접속할 K3s Server IP"
  value       = aws_instance.k3s_server.public_ip
}

#Agent IP 리스트 출력은 삭제

output "nlb_dns" {
  description = "Nginx 접속용 NLB DNS 주소"
  value       = aws_lb.k3s_nlb.dns_name
}