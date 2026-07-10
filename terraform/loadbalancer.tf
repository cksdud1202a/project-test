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