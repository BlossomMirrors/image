# regenerate the grub config
update:
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# add a kernel argument to every boot entry
add-karg karg:
    sudo grubby --update-kernel=ALL --args="{{ karg }}"

# remove a kernel argument from every boot entry
remove-karg karg:
    sudo grubby --update-kernel=ALL --remove-args="{{ karg }}"
