#!/bin/bash

echo "🔍 K3s Cluster Health Status"
echo "===================================="

# 1. 노드 연결 테스트
echo "1. Testing node connectivity via Ansible..."
ansible all -m ping

# 2. 클러스터 노드 상태 확인 (K3s Server에서 실행)
echo "2. Checking K3s node status..."
# 'masters' 그룹을 그대로 유지하거나, 구조 변경에 따라 'servers'로 수정 가능합니다.
ansible servers -m shell -a "kubectl get nodes -o wide"

# 3. 모든 네임스페이스의 포드 상태 확인
# K3s는 내장된 Flannel, CoreDNS, Metrics-server 등이 잘 떠있는지 확인하는 것이 핵심입니다.
echo "3. Checking system pods status..."
ansible servers -m shell -a "kubectl get pods -A"

# 4. 서비스 가동 상태 확인 (K3s 맞춤형)
# K3s는 Server 노드에서는 'k3s', Agent 노드에서는 'k3s-agent' 서비스를 사용합니다.
echo "4. Checking K3s service status on all nodes..."
echo "--- [Servers] ---"
ansible servers -m shell -a "systemctl is-active k3s" || echo "❌ K3s Server is not running"
echo "--- [Agents] ---"
ansible agents -m shell -a "systemctl is-active k3s-agent" || echo "❌ K3s Agent is not running"

# 5. [추가] K3s 리소스 사용량 확인 (Metrics-server 내장 활용)
echo "5. Checking resource usage (CPU/Memory)..."
ansible servers -m shell -a "kubectl top nodes" || echo "⚠️ Metrics-server is starting up or not ready."

echo "✅ K3s Health Status check completed!"
