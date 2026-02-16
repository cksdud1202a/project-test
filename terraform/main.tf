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
  
  # [중요] 타 노드의 트래픽을 전달하기 위해 원본/대상 확인 해제 (NAT 역할 수행용)
  #AWS 인스턴스가 자신을 목적지로 하지 않는 트래픽도 전달할 수 있게 허용하는 설정
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

  # 중요: Ansible Dynamic Inventory가 인식할 태그
  tags = {
    Name           = "${var.project_name}-server"
    Project        = "k3s-project"    # 전체 프로젝트 식별자
    Role           = "server"         # 서버 그룹 분류용
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

  # Server가 먼저 설치되어야 Agent가 참여할 수 있음
  depends_on = [aws_instance.k3s_server]

  user_data = <<-EOF
              #!/bin/bash
              # 1. Swap 설정
              fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. 라우팅 테이블 수정 (인터넷 기본 통로를 Server 서버로 변경)
              SERVER_IP="${aws_instance.k3s_server.private_ip}"
              ip route add 192.168.1.0/24 dev eth0 # Server와 내부 통신 유지
              ip route replace default via $SERVER_IP dev eth0

              # 3. K3s Agent 설치 (Server가 준비될 때까지 재시도)
              until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
                K3S_TOKEN="${var.k3s_token}" sh -s - agent; do
                sleep 10
              done
              EOF

  # 중요: Ansible Dynamic Inventory가 인식할 태그
  tags = {
    Name    = "${var.project_name}-agent-${count.index + 1}"
    Project = "k3s-project"    # 전체 프로젝트 식별자
    Role    = "agent"          # 에이전트 그룹 분류용
    ServerPublicIP = aws_instance.k3s_server.public_ip
  }
}
