#!/bin/bash

# 에러 발생 시 즉시 중단하여 잘못된 설정이 퍼지는 것을 방지합니다.
set -e

echo "🚀 K3s 클러스터 통합 배포를 시작합니다..."

# 1. Ansible 설치 여부 확인
if ! command -v ansible &> /dev/null; then
    echo "❌ Ansible이 설치되어 있지 않습니다. 아래 명령어로 설치를 먼저 진행해 주세요:"
    echo "    sudo apt update && sudo apt install ansible -y"
    exit 1
fi

# 2. 모든 노드(Server & Agents) 연결 테스트
# inventory/hosts.yml에 정의된 노드들에 SSH 접속이 가능한지 확인합니다.
echo "🔍 모든 노드에 대한 연결 상태를 점검 중..."
ansible all -m ping

# 3. 전체 플레이북 실행
# site.yml은 common, server, agent 역할을 순서대로 호출합니다.
echo "📦 K3s 전체 설치 프로세스 가동 (site.yml)..."
ansible-playbook site.yml

echo ""
echo "✅ K3s 클러스터 배포가 성공적으로 완료되었습니다!"
echo ""

# 4. 클러스터 접근 방법 안내
echo "🔧 클러스터 제어 방법:"
echo "    ssh <사용자계정>@<Server_IP>"
echo "    kubectl get nodes"
echo ""

# 5. 로컬에서 원격 제어를 위한 kubeconfig 복사 안내
echo "📋 로컬 PC에서 kubectl을 사용하고 싶다면:"
echo "    mkdir -p ~/.kube"
echo "    scp <사용자계정>@<Server_IP>:~/.kube/config ~/.kube/config"
echo "    # 주의: ~/.kube/config 파일 내의 server 주소를 127.0.0.1에서 Server_IP로 수정해야 합니다."

echo ""
echo "🔍 클러스터 상태 최종 확인 중..."
# masters 그룹 대신 K3s 명칭인 'servers' 또는 인벤토리 그룹명을 사용합니다.
ansible servers -m shell -a "kubectl get nodes -o wide"

echo ""
echo "✅ 클러스터 준비 완료!"
