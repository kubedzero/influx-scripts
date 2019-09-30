* https://itnext.io/upgrading-bash-on-macos-7138bd1066ba explains why Bash 3.2 is still on macOS and how to get Bash 4 with Homebrew
* https://www.shellcheck.net/ can offer suggestions to do shell scripting better
* https://github.com/lovesegfault/beautysh installed via pip is helpful to format shell script files from the command line
* Installed Bash 5 on macOS which had readarray -d but Bash 4.2 on CentOS did not have it. Updating to bash 5 with https://www.ramoonus.nl/2019/01/08/bash-5-0-installation-for-linux/ and then changing line1 to point to the compiled version
* https://apple.stackexchange.com/questions/55989/change-my-shell-to-a-different-bash-version-at-usr-local-bin-bash change the default shell per username by editing `/etc/shells` and then running `chsh -s /usr/local/bin/bash username` to set the version you want for your username.
```
[user@localhost ~]# cat /etc/shells 
/bin/sh
/bin/bash
/usr/bin/sh
/usr/bin/bash
[user@localhost ~]# echo /usr/local/sbin/bash >> /etc/shells
[user@localhost ~]# chsh -s /usr/local/sbin/bash user
Changing shell for user.
Shell changed.
```