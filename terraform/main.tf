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
# [추가] Agent AZ(2b)용 Public Subnet
# NLB가 Agent와 같은 AZ에 ENI를 가지기 위해 필요
# ===============================
resource "aws_subnet" "public_2b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.3.0/24"
  availability_zone       = "ap-northeast-2b"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-subnet-2b" }
}

resource "aws_route_table_association" "public_2b_assoc" {
  subnet_id      = aws_subnet.public_2b.id
  route_table_id = aws_route_table.public_rt.id
}

# ===============================
# Network Load Balancer
# ===============================
resource "aws_lb" "k3s_nlb" {
  name               = "k3s-nlb"
  load_balancer_type = "network"
  internal           = false
  # [변경] 2b Public Subnet 추가 → NLB가 Agent AZ에 ENI 생성
  subnets            = [aws_subnet.public.id, aws_subnet.public_2b.id]

  enable_cross_zone_load_balancing = true

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
# Agent만 Target Group에 등록
# ===============================
resource "aws_lb_target_group_attachment" "agents" {
  count            = length(aws_instance.k3s_agent)
  target_group_arn = aws_lb_target_group.nginx_tg.arn
  target_id        = aws_instance.k3s_agent[count.index].id
  port             = 30080
}

# 전체 트래픽 흐름:
# 사용자 → NLB:80 → Listener → Agent1:30080 또는 Agent2:30080 → Nginx Pod