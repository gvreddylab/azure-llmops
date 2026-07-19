resource "azurerm_subnet" "relay" {
  name                 = "subnet-relay"
  resource_group_name  = azurerm_resource_group.llmresgrp.name
  virtual_network_name = azurerm_virtual_network.llmops.name
  address_prefixes     = var.relay_subnet_prefix
}

resource "azurerm_public_ip" "relay" {
  name                = "${var.project_name}-relay-pip"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["2"]
}

resource "azurerm_network_security_group" "relay" {
  name                = "${var.project_name}-relay-nsg"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name

  security_rule {
    name                       = "AllowSSHFromMyIP"
    priority                   = 100
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "22"
    source_address_prefix        = var.allowed_ssh_source_ip
    destination_address_prefix   = "*"
  }
}

resource "azurerm_network_interface" "relay" {
  name                = "${var.project_name}-relay-nic"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name

  ip_configuration {
    name                         = "internal"
    subnet_id                    = azurerm_subnet.relay.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.relay.id
  }
}

resource "azurerm_network_interface_security_group_association" "relay" {
  network_interface_id      = azurerm_network_interface.relay.id
  network_security_group_id = azurerm_network_security_group.relay.id
}

resource "azurerm_linux_virtual_machine" "relay" {
  name                = "${var.project_name}-relay-vm"
  resource_group_name = azurerm_resource_group.llmresgrp.name
  location            = azurerm_resource_group.llmresgrp.location
  size                = "Standard_D2als_v7"
  admin_username      = var.relay_admin_username
  zone                = "2"

  network_interface_ids = [azurerm_network_interface.relay.id]

  admin_ssh_key {
    username   = var.relay_admin_username
    public_key = var.relay_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-CLOUDINIT
    #!/bin/bash
    curl -fsSL https://tailscale.com/install.sh | sh
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p
    tailscale up --authkey=${var.tailscale_auth_key} --advertise-routes=${var.vnet_address_space[0]} --accept-dns=false
  CLOUDINIT
  )
}

output "relay_vm_public_ip" {
  value = azurerm_public_ip.relay.ip_address
}
