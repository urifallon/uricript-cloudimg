# uricript-cloudimg

Dưới đây là README hoàn chỉnh cho script `make-seed.sh` (tạo NoCloud seed ISO cho Ubuntu cloud image chạy KVM/libvirt).

---

# README — `make-seed.sh` (NoCloud seed ISO for KVM/libvirt)

## Mục đích

`make-seed.sh` tạo một **cloud-init NoCloud seed ISO** để boot **Ubuntu cloud image** trên KVM/libvirt trong môi trường headless, đảm bảo:

* Tạo user `ubuntu` với quyền `sudo` không cần mật khẩu
* Inject SSH public key (từ private key bạn cung cấp)
* Cài và bật `openssh-server` để SSH được
* Cài và bật `qemu-guest-agent` để có thể lấy IP bằng `virsh domifaddr --source agent`
* Cấu hình mạng **DHCP** (không hardcode MAC)

Script này tập trung vào **bootstrap đường SSH** (LAN DHCP) để bạn vào VM trước; cấu hình các NIC/network còn lại nên làm sau khi SSH.

---

## Môi trường áp dụng

### Host OS

* Ubuntu/Debian-based Linux (khuyến nghị Ubuntu 20.04+ / 22.04+ / 24.04+)
* Có quyền `sudo`

### Virtualization stack

* KVM + libvirt (`qemu:///system`)
* VM dùng **Ubuntu cloud image** (ví dụ `noble-server-cloudimg-amd64.img`, `jammy-server-cloudimg-amd64.img`)

### Packages cần có (script tự cài)

* `cloud-image-utils` (cung cấp `cloud-localds`)
* `openssh-client` (để có `ssh-keygen`, thường có sẵn)

---

## Cơ chế hoạt động

1. Script kiểm tra private key tồn tại và chỉnh permission đúng chuẩn SSH:

   * `~/.ssh` → `700`
   * private key → `600`
2. Dùng `ssh-keygen -y` trích xuất public key từ private key
3. Tạo 3 file cloud-init:

   * `user-data`: tạo user, inject key, cài `openssh-server`, `qemu-guest-agent`, bật service
   * `meta-data`: đặt `instance-id` và hostname (instance-id tự thay đổi theo timestamp để cloud-init không bỏ qua)
   * `network-config`: bật DHCP (không map theo MAC)
4. Dùng `cloud-localds` build thành **ISO** và đặt vào `/var/lib/libvirt/images/`

---

## Đầu vào (Inputs)

Script nhận tối đa 3 tham số:

```bash
./make-seed.sh <VM_NAME> <PRIVATE_KEY_PATH> <SEED_ISO_OUTPUT>
```

* `VM_NAME` (tuỳ chọn, mặc định `bootstap`)

  * Dùng để đặt hostname và instance-id
* `PRIVATE_KEY_PATH` (tuỳ chọn, mặc định `~/.ssh/urissh`)

  * Private key dùng để tạo public key inject vào VM
* `SEED_ISO_OUTPUT` (tuỳ chọn, mặc định `/var/lib/libvirt/images/<VM_NAME>-seed.iso`)

  * Đường dẫn output file seed ISO

Ví dụ:

```bash
./make-seed.sh bootstap ~/.ssh/urissh /var/lib/libvirt/images/bootstap-seed.iso
```

---

## Đầu ra (Outputs)

* File seed ISO:
  `/<...>/bootstap-seed.iso` (mặc định `/var/lib/libvirt/images/<VM_NAME>-seed.iso`)

* Public key được tạo (cạnh private key):
  `~/.ssh/urissh.pub`

* Console output: đường dẫn ISO và gợi ý lấy IP bằng guest-agent

---

## Cài đặt & sử dụng

### 1) Lưu script và cấp quyền chạy

```bash
chmod +x make-seed.sh
```

### 2) Tạo seed ISO

```bash
./make-seed.sh bootstap ~/.ssh/urissh /var/lib/libvirt/images/bootstap-seed.iso
```

---

## Cách dùng seed ISO với VM

### Khuyến nghị: boot lần đầu chỉ với 1 NIC (LAN) để DHCP chắc chắn

Khi không map MAC, nếu VM có nhiều NIC ngay từ đầu thì DHCP có thể apply “nhầm NIC”. An toàn nhất là:

1. Tạo VM với **một NIC** nối `br-lan` + gắn seed ISO
2. Sau khi SSH được, attach thêm các NIC còn lại (`br-mgmt/br-api/...`) và cấu hình netplan trong VM

Ví dụ tạo VM (tham khảo):

```bash
sudo virt-install \
  --name bootstap \
  --memory 4096 --vcpus 4 --cpu host-passthrough \
  --import \
  --osinfo detect=on,require=off \
  --disk path=/var/lib/libvirt/images/bootstap.qcow2,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/bootstap-seed.iso,device=cdrom \
  --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
  --graphics none --console pty,target_type=serial --noautoconsole \
  --network bridge=br-lan,model=virtio
```

### Lấy IP bằng guest-agent

Sau khi VM boot (30–90s):

```bash
sudo virsh domifaddr bootstap --source agent
```

Sau đó SSH:

```bash
ssh -i ~/.ssh/urissh ubuntu@<IP>
```

---

## Giới hạn và lưu ý quan trọng

### 1) Không map MAC ⇒ không đảm bảo cấu hình multi-NIC ngay từ boot

Nếu VM có nhiều NIC khi boot lần đầu, DHCP/default route có thể rơi vào NIC không mong muốn. Đó là lý do workflow khuyến nghị boot lần đầu chỉ 1 NIC.

### 2) Cloud-init có thể “bỏ qua” nếu instance-id không đổi

Script tự thêm timestamp vào `instance-id` để tránh cloud-init coi là “đã init rồi”.

### 3) Quyền private key

Nếu private key có permission quá mở (ví dụ 664), `ssh/ssh-keygen` sẽ từ chối dùng. Script tự sửa về `600`.

---

## Troubleshooting

### Seed ISO tạo xong nhưng VM không SSH được

1. Check IP:

   ```bash
   sudo virsh domifaddr <vm> --source agent
   ```
2. Check port 22:

   ```bash
   nc -vz <IP> 22
   ```
3. Xem log QEMU:

   ```bash
   sudo tail -n 200 /var/log/libvirt/qemu/<vm>.log
   ```
4. Nếu cần bắt DHCP/ARP:

   ```bash
   sudo tcpdump -i br-lan -nn -e '(udp port 67 or 68) or arp'
   ```

---

## Security Notes

* Script cấp quyền `ubuntu` sudo NOPASSWD (phù hợp lab, không khuyến nghị production).
* SSH password bị tắt (`ssh_pwauth: false`).
* Root bị disable login (`disable_root: true`).
