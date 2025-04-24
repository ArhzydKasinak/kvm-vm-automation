#!/bin/bash

set -e

echo "🔧 Устанавливаем необходимые пакеты..."
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager ansible python3-libvirt

echo "👤 Добавляем пользователя в группу libvirt..."
sudo usermod -aG libvirt "$USER"

echo "🌐 Проверяем наличие моста br0..."
if ! ip link show br0 > /dev/null 2>&1; then
  echo "🔧 Мост br0 не найден, создаём..."

  # Уточни, какой интерфейс будет в качестве физического (например, eth0 или enp1s0)
  # Здесь просто пример с интерфейсом eth0
  read -p "Введите имя физического интерфейса для моста (например, eth0): " phys_iface

  # Создание Netplan-конфигурации (для Ubuntu 18.04+)
  sudo bash -c "cat > /etc/netplan/01-br0.yaml" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${phys_iface}:
      dhcp4: no
  bridges:
    br0:
      interfaces: [${phys_iface}]
      dhcp4: yes
EOF

  echo "💾 Применяем настройки сети..."
  sudo netplan apply
else
  echo "✅ Мост br0 уже существует."
fi

echo "📁 Создаём структуру проекта..."
mkdir -p ~/kvm_vm_automation/{roles/create_vm/{tasks,templates},}
cd ~/kvm_vm_automation

echo "🗂️ Создаём инвентарный файл..."
cat <<EOF > inventory
localhost ansible_connection=local
EOF

echo "📜 Создаём Ansible playbook..."
cat <<EOF > create_vms.yml
- name: Create VMs from QCOW2 template
  hosts: localhost
  gather_facts: no

  vars_prompt:
    - name: vm_base_name
      prompt: "Введите базовое имя ВМ (например, vm)"
      private: no
    - name: vm_count
      prompt: "Сколько ВМ создать?"
      private: no
    - name: qcow2_image
      prompt: "Путь к образу QCOW2?"
      private: no

  tasks:
    - name: Создать XML-конфигурацию для ВМ
      template:
        src: roles/create_vm/templates/vm.xml.j2
        dest: "/tmp/{{ vm_base_name }}{{ item }}.xml"
      loop: "{{ range(1, vm_count | int + 1) | list }}"

    - name: Определить и запустить виртуальную машину
      community.libvirt.virt:
        command: define
        xml: "/tmp/{{ vm_base_name }}{{ item }}.xml"
      loop: "{{ range(1, vm_count | int + 1) | list }}"

    - name: Запустить ВМ
      community.libvirt.virt:
        name: "{{ vm_base_name }}{{ item }}"
        state: running
      loop: "{{ range(1, vm_count | int + 1) | list }}"

    - name: Удалить временные XML файлы
      file:
        path: "/tmp/{{ vm_base_name }}{{ item }}.xml"
        state: absent
      loop: "{{ range(1, vm_count | int + 1) | list }}"
EOF

echo "📄 Создаём шаблон конфигурации ВМ..."
cat <<EOF > roles/create_vm/templates/vm.xml.j2
<domain type='kvm'>
  <name>{{ vm_base_name }}{{ item }}</name>
  <memory unit='MiB'>2048</memory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='{{ qcow2_image }}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='bridge'>
      <source bridge='br0'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' listen='0.0.0.0'/>
  </devices>
</domain>
EOF

echo "✅ Готово! Чтобы запустить создание ВМ, выполните:"
echo "  cd ~/kvm_vm_automation"
echo "  ansible-playbook -i inventory create_vms.yml"

echo "💡 Примечание: после установки добавьте bridge 'br0', если он ещё не создан."
