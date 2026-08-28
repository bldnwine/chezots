# Installation

```bash
# 0. Enable multilib
sudo nano /etc/pacman.conf
# Uncomment:
# [multilib]
# Include = /etc/pacman.d/mirrorlist
sudo pacman -Sy

# 1. Install prerequisites
sudo pacman -S --needed git base-devel chezmoi

# 2. Deploy dotfiles
chezmoi init --apply https://github.com/bldnwine/chezots.git

# 3. Install packages
~/owlcat/initial/chezup
```
