# 최신 Ubuntu AMI 자동 검색
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-*-amd64-server-*"]
  }
  owners = ["099720109477"]
}

# 1. Server 인스턴스 (NAT + Bastion + K3s Server)
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.server_sg.id]
  source_dest_check      = false

  user_data = <<-EOF
    #!/bin/bash
    # Swap 설정
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # NAT 설정
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
    
    # K3s 서버 설치
    curl -sfL https://get.k3s.io | K3S_TOKEN="${var.k3s_token}" sh -s - server \
      --node-ip $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
      --write-kubeconfig-mode 644
  EOF

  # 🔥 중요! Ansible이 인식할 태그 추가
  tags = {
    Name           = "${var.project_name}-server"   # 보기 좋은 이름
    Role           = "server"                        # Ansible이 이걸로 그룹 분류!
    ServerPublicIP = self.public_ip                  # Agent들이 SSH 접속할 때 사용
  }
}

# 2. Agent 인스턴스 (K3s Agent)
resource "aws_instance" "k3s_agent" {
  count                  = var.agent_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.agent_sg.id]

  depends_on = [aws_instance.k3s_server]

  user_data = <<-EOF
    #!/bin/bash
    # Swap 설정
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # 라우팅 설정
    SERVER_IP="${aws_instance.k3s_server.private_ip}"
    ip route add 192.168.1.0/24 dev eth0
    ip route replace default via $SERVER_IP dev eth0

    # K3s Agent 설치
    until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
      K3S_TOKEN="${var.k3s_token}" sh -s - agent; do
      sleep 10
    done
  EOF

  # 🔥 중요! Ansible이 인식할 태그 추가
  tags = {
    Name    = "${var.project_name}-agent-${count.index + 1}"
    Role    = "agent"          # Ansible이 이걸로 agents 그룹 분류!
  }
}