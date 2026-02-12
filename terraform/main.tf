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

  tags = { Name = "${var.project_name}-server" }
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

  # EBS 추가 (EC2 삭제돼도 데이터 유지)
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = 10        # 10GB (프리티어 30GB 안에서 무료)
    volume_type           = "gp2"
    delete_on_termination = false     # EC2 삭제돼도 EBS는 남아있음
  }

  user_data = <<-EOF
          #!/bin/bash
          set -x  # 디버깅용
          exec > >(tee /var/log/user-data.log) 2>&1  # 로그 저장
          
          # 1. Swap 설정
          fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
          echo '/swapfile none swap sw 0 0' >> /etc/fstab
          
          # 2. EBS 마운트 (Prometheus 데이터 저장용)
          while [ ! -e /dev/sdf ]; do
            echo "Waiting for EBS volume..."
            sleep 5
          done
          mkfs.ext4 -F /dev/sdf
          mkdir -p /data/prometheus
          mount /dev/sdf /data/prometheus
          echo '/dev/sdf /data/prometheus ext4 defaults 0 0' >> /etc/fstab
          
          # 3. K3s Agent 설치 (라우팅 변경 전에 먼저!)
          SERVER_IP="${aws_instance.k3s_server.private_ip}"
          until curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" \
            K3S_TOKEN="${var.k3s_token}" sh -s - agent \
            --node-ip $(hostname -I | awk '{print $1}'); do
            echo "K3s installation failed, retrying in 10s..."
            sleep 10
          done
          
          # 4. K3s 설치 완료 후 라우팅 테이블 수정
          sleep 5
          ip route add 192.168.1.0/24 dev eth0 || true
          ip route replace default via $SERVER_IP dev eth0
          
          echo "User data completed successfully" >> /var/log/user-data.log
          EOF

  tags = { Name = "${var.project_name}-agent-${count.index}" }
}
