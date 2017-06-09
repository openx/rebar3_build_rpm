Conventions
-----------
1. contents of directory 'slash' will be copied into '/' of the package
2. if the directory 'internal' exists the following scripts will be looked for
and added to the rpm
  a. pre.sh - run at the pre-install script of rpm installation
  b. post.sh - run at the post-install script of rpm installation
  c. preun.sh - run before uninstalling or upgrading
  d. postun.sh - run after uninstalling or upgrading
