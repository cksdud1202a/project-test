#!/bin/bash

# 동적 인벤토리 파일 경로를 변수로 지정하여 관리를 편하게 합니다.
INV="inventory/hosts.aws_ec2.yml"

echo "🔍 K3s Cluster Health Status (Dynamic Inventory)"
echo "===================================================="

# 1. 노드 연결 테스트
echo "1. Testing node connectivity via Ansible..."
ansible all -i $INV -m ping

# 2. 클러스터 노드 상태 확인
echo -e "\n2. Checking K3s node status..."
# 동적 인벤토리 그룹명 'servers' 사용
ansible servers -i $INV -m shell -a "kubectl get nodes -o wide"

# 3. 모든 네임스페이스의 포드 상태 확인
echo -e "\n3. Checking system pods status..."
# [수정]: severs -> servers 오타 수정 및 인벤토리 경로 추가
ansible servers -i $INV -m shell -a "kubectl get pods -A"

# 4. 서비스 가동 상태 확인
echo -e "\n4. Checking K3s service status on all nodes..."
echo "--- [Servers] ---"
ansible servers -i $INV -m shell -a "systemctl is-active k3s"

echo "--- [Agents] ---"
ansible agents -i $INV -m shell -a "systemctl is-active k3s-agent"

# 5. 리소스 사용량 확인 (Metrics-server 내장 활용)
echo -e "\n5. Checking resource usage (CPU/Memory)..."
# 에러 메시지를 깔끔하게 처리하기 위해 2>/dev/null 추가
ansible servers -i $INV -m shell -a "kubectl top nodes" 2>/dev/null || echo "⚠️ Metrics-server is starting up or not ready."

echo -e "\n✅ K3s Health Status check completed!"