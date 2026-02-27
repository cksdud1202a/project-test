# 최신 Ubuntu AMI 자동 검색
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
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
              # 1. Swap 메모리 설정
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. NAT 설정
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
              iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              
              # 3. K3s Server 설치
              curl -sfL https://get.k3s.io | K3S_TOKEN="${var.k3s_token}" sh -s - server \
                --node-ip $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
                --write-kubeconfig-mode 644
              EOF

  tags = {
    Name           = "${var.project_name}-server"
    Project        = "k3s-project"
    Role           = "servers"
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
              # 1. Swap 설정
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # [변경] ip route 수정 제거
              # Private Route Table에서 이미 Server ENI를 NAT로 설정했으므로
              # OS 레벨에서 라우팅 수정하면 비대칭 라우팅 문제 발생
              SERVER_IP="${aws_instance.k3s_server.private_ip}"

              # 2. K3s Agent 설치 (Server가 준비될 때까지 재시도)
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent; do
                sleep 10
              done
              EOF

  tags = {
    Name           = "${var.project_name}-agent-${count.index + 1}"
    Project        = "k3s-project"
    Role           = "agents"
    ServerPublicIP = aws_instance.k3s_server.public_ip
  }
}

# ===============================
# Network Load Balancer
# ===============================
resource "aws_lb" "k3s_nlb" {
  name               = "k3s-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.public.id]

  tags = {
    Name = "k3s-nlb"
  }
}

# ===============================
# Target Group (NodePort 30080)
# ===============================
resource "aws_lb_target_group" "nginx_tg" {
  name        = "k3s-nginx-tg"
  port        = 30080
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "30080"
  }
}

# ===============================
# Listener (외부 80 → 내부 30080)
# ===============================
resource "aws_lb_listener" "nginx_listener" {
  load_balancer_arn = aws_lb.k3s_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_tg.arn
  }
}

# ===============================
# [변경] Server attachment 제거
# Agent만 Target Group에 등록
# NLB → Agent 직접 연결 (VPC 내부 통신으로 Private Subnet도 가능)
# ===============================
resource "aws_lb_target_group_attachment" "agents" {
  count            = length(aws_instance.k3s_agent)
  target_group_arn = aws_lb_target_group.nginx_tg.arn
  target_id        = aws_instance.k3s_agent[count.index].id
  port             = 30080
}

# 전체 트래픽 흐름:
# 사용자 → NLB:80 → Listener → Agent1:30080 또는 Agent2:30080 → Nginx Pod