Conventions
-----------
When building a release and using overlays the resulting release directory
layout is used to build rpms.  The following conventions will be applied

1. the release itself will be install in /usr/lib64/release_name/ unless the prefix is overridden.
2. the contents of the directory 'slash' will be copied into '/' of the package.  'slash' should exist at the top level of the release.
3. if the directory 'slash/internal' exists the following scripts will be looked
   for and added to the rpm (but will not exist as files in the final rpm)
  * pre.sh - run at the pre-install script of rpm installation
  * post.sh - run at the post-install script of rpm installation
  * preun.sh - run before uninstalling or upgrading
  * postun.sh - run after uninstalling or upgrading
