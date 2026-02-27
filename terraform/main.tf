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
              # 1. Swap 메모리 설정 (1GB RAM 환경 필수)
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. NAT 설정 (IP Forwarding 활성화 및 IPTables 규칙 추가)
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

              # 2. 라우팅 테이블 수정
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0
              ip route replace default via $SERVER_IP dev eth0

              # 3. K3s Agent 설치 (Server가 준비될 때까지 재시도)
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
# 외부 사용자가 Nginx에 접속할 때 단일 진입점 역할
# ===============================
resource "aws_lb" "k3s_nlb" {
  name               = "k3s-nlb"          # AWS에서 보이는 NLB 이름
  load_balancer_type = "network"           # TCP 레벨에서 트래픽 처리

  internal           = false               # 인터넷에서 접근 가능
  subnets            = [aws_subnet.public.id]  # 외부 트래픽을 받아야 하니까 Public Subnet에 위치

  tags = {
    Name = "k3s-nlb"
  }
}

# ===============================
# Target Group (NodePort 30080)
# NLB가 트래픽을 어느 서버로 보낼지 목록
# 여기에 Server 노드를 등록해두면 NLB가 이 목록을 보고 트래픽을 전달
# ===============================
resource "aws_lb_target_group" "nginx_tg" {
  name        = "k3s-nginx-tg"      # Target Group 이름
  port        = 30080                # 트래픽을 전달할 대상 포트 (K3s NodePort)
  protocol    = "TCP"                # TCP 프로토콜로 전달
  vpc_id      = aws_vpc.main.id      # 어느 VPC 안에서 동작할지 지정
  target_type = "instance"           # 대상이 EC2 인스턴스임을 명시

  health_check {
    protocol = "TCP"      # TCP 연결로 대상 인스턴스가 살아있는지 확인
    port     = "30080"    # 30080 포트로 Health Check (Nginx가 응답하면 Healthy)
  }
  # Health Check 흐름:
  # NLB → Server:30080 TCP 연결 시도
  # 성공 → Healthy → 트래픽 전달
  # 실패 → Unhealthy → 트래픽 차단
}

# ===============================
# Listener (외부 80 → 내부 30080)
# NLB가 어느 포트로 들어오는 트래픽을 받을지, 그리고 어디로 보낼지 규칙
# ===============================
resource "aws_lb_listener" "nginx_listener" {
  load_balancer_arn = aws_lb.k3s_nlb.arn          # 어느 NLB에 붙일지 지정
  port              = 80                            # 외부에서 접속하는 포트 (사용자가 80으로 접속)
  protocol          = "TCP"                         # TCP 프로토콜로 수신

  default_action {
    type             = "forward"                         # 수신한 트래픽을 Target Group으로 전달
    target_group_arn = aws_lb_target_group.nginx_tg.arn  # 위에서 만든 Target Group으로 포워딩
  }
  # 동작 흐름:
  # 사용자가 NLB:80으로 접속
  # → Listener가 수신
  # → nginx_tg Target Group으로 포워딩
  # → Server:30080으로 전달
}

# ===============================
# Attach Server Node Only
# Server의 kube-proxy가 Agent의 Nginx Pod으로 라우팅해줌
# ===============================
resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.nginx_tg.arn  # 어느 Target Group에 붙일지
  target_id        = aws_instance.k3s_server.id         # 대상 EC2 인스턴스 (Server 노드)
  port             = 30080                              # 트래픽을 전달할 포트
  # Agent를 붙이지 않는 이유:
  # Agent는 Private Subnet에 있어서 NLB가 직접 Health Check 불가
  # 대신 Server의 kube-proxy가 내부적으로
  # Agent1(192.168.2.145)의 Nginx Pod
  # Agent2(192.168.2.157)의 Nginx Pod
  # 으로 자동 분산 라우팅해줌
}

# 전체 트래픽 흐름:
# 사용자 → NLB:80 → Listener → Server:30080 → kube-proxy → Agent1 Nginx Pod
#                                                          → Agent2 Nginx Pod