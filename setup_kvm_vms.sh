#!/bin/bash

# Этот скрипт автоматически выполнит все нужные установки и настройки для автоматизации создания ВМ с помощью KVM и Ansible.

# Установка необходимых пакетов
echo "Устанавливаем необходимые пакеты..."
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager ansible

# Добавление пользователя в группу libvirt
echo "Добавляем пользователя в группу libvirt..."
sudo usermod -aG libvirt $USER
newgrp libvirt

# Подготовка рабочей директории
echo "Создаём директорию для проекта..."
mkdir -p ~/kvm_vm_automation
cd ~/kvm_vm_automation

# Создание инвентарного файла для Ansible
echo "Создаём инвентарный файл для Ansible..."
cat <<EOL > inventory
localhost ansible_connection=local
EOL

# Создание файла main.yml для Ansible
echo "Создаём основной Playbook для Ansible..."
cat <<EOL > create_vms.yml
- name: Create VMs from QCOW2 template
  hosts: localhost
  gather_facts: no

  vars_prompt:
    - name: "vm_base_name"
      prompt: "Введите базовое имя ВМ (например, vm)"
      private: no
    - name: "vm_count"
      prompt: "Сколько ВМ создать?"
      private: no
    - name: "qcow2_image"
      prompt: "Путь к образу QCOW2?"
      private: no

  tasks:
    - name: Create virtual machine from QCOW2 template
      virt:
        name: "{{ vm_base_name }}{{ item }}"
        state: defined
        vcpu: 2
        memory_mb: 2048
        disk:
          size: 20
          image: "{{ qcow2_image }}"
        network:
          - bridge: br0
        graphics: vnc
      loop: "{{ range(1, vm_count | int + 1) | list }}"

    - name: Start virtual machines
      virt:
        name: "{{ vm_base_name }}{{ item }}"
        state: running
      loop: "{{ range(1, vm_count | int + 1) | list }}"
EOL

# Создание роли Ansible для виртуальных машин
echo "Создаём структуру для роли Ansible..."
mkdir -p roles/create_vm/tasks
mkdir -p roles/create_vm/templates
mkdir -p roles/create_vm/vars

# Шаблон XML для виртуальных машин
echo "Создаём шаблон для конфигурации ВМ (vm.xml.j2)..."
cat <<EOL > roles/create_vm/templates/vm.xml.j2
<domain type='kvm'>
  <name>{{ vm_name }}</name>
  <memory unit='KiB'>{{ vm_memory }}</memory>
  <vcpu placement='static'>{{ vm_vcpu }}</vcpu>
  <disk type='file' device='disk'>
    <driver name='qemu' type='qcow2'/>
    <source file='/var/lib/libvirt/images/{{ vm_name }}.qcow2'/>
    <target dev='vda' bus='virtio'/>
  </disk>
  <interface type='bridge'>
    <mac address='52:54:00:00:00:00'/>
    <source bridge='{{ vm_bridge }}'/>
    <model type='virtio'/>
  </interface>
</domain>
EOL

# Основная задача для роли create_vm
echo "Создаём основную задачу для роли..."
cat <<EOL > roles/create_vm/tasks/main.yml
- name: Create VMs from QCOW2 image
  include_tasks: create_one_vm.yml
EOL

# Задача для создания одной ВМ
echo "Создаём задачу для создания одной ВМ..."
cat <<EOL > roles/create_vm/tasks/create_one_vm.yml
- name: Define and start VM {{ vm_name }}
  virt:
    name: "{{ vm_name }}"
    state: defined
    vcpu: 2
    memory_mb: 2048
    disk:
      size: 20
      image: "{{ qcow2_image }}"
    network:
      - bridge: br0
    graphics: vnc
EOL

# Уведомление об окончании установки
echo "Все необходимые файлы созданы."

# Инструкции для пользователя
echo "Инструкция:"
echo "1. Подготовьте образ QCOW2 (например, Debian или Ubuntu) и разместите его на сервере."
echo "2. Запустите Ansible Playbook:"
echo "   ansible-playbook -i inventory create_vms.yml"
echo "3. Введите параметры: имя ВМ, количество ВМ и путь к образу QCOW2."

# Завершение работы
echo "Готово! Вы можете использовать Ansible для создания виртуальных машин."
