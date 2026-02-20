output "server_public_ip" {
  description = "외부에서 접속할 K3s Server IP"
  value       = aws_instance.k3s_server.public_ip
}

# Agent IP 리스트 출력은 삭제!
# Ansible이 AWS API로 직접 찾을 거니까 필요 없음
# 참고용으로 남김