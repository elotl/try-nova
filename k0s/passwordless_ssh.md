# Setting up password-less SSH to your VMware Fusion Ubuntu VMs


The scripts in this doc assume that your VMs are named 'ubuntu-vm1' and 'ubuntu-vm2'
with username="test" and password="test".

## Generate SSH keys
```ssh
VM_USER=test VM_PASSWORD=test ./vm_manager.sh setup-ssh
```

Note:
- You might have to remove your key from `/Users/<user>/.ssh/known_hosts`, if you see an error as shown below:
	
```ssh
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 2 key(s) remain to be installed -- if you are prompted now it is to install the new keys
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:RKmvCzH/tHo8sR0IU96eHGkcFfk01cYL6TGPM256IcQ.
Please contact your system administrator.
Add correct host key in /Users/<user>/.ssh/known_hosts to get rid of this message.
Offending ECDSA key in /Users/<user>/.ssh/known_hosts:40
Password authentication is disabled to avoid man-in-the-middle attacks.
Keyboard-interactive authentication is disabled to avoid man-in-the-middle attacks.
UpdateHostkeys is disabled because the host key is not trusted.
test@192.168.1.71: Permission denied (publickey,password).
```


Run:
```ssh
ssh-keygen -R 192.168.1.85
```

## Setup passwordless sudo


SSH into your VM:
```ssh
ssh test@192.168.1.85
```

Once logged in, run:
```ssh
echo 'test ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/test
sudo chmod 440 /etc/sudoers.d/test
exit
```

Ensure that sudo commands can be executed without password:

```
ssh test@192.168.1.85 sudo apt-get update
```

# if it still requires a password try this
cat ~/.ssh/id_rsa.pub | ssh test@192.168.1.85 "cat > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

