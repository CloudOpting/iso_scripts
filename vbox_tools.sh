KERN_DIR=/usr/src/kernels/`uname -r`
export KERN_DIR
mkdir /media/cdrom/
mount /dev/cdrom /media/cdrom/
cd /media/cdrom
./VBoxLinuxAdditions.run
