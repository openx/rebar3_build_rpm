Motivation
----------
This rebar3 plugin was developed to allow packaging of rebar3 releases as
an rpm.  In order to do so it pulled in [epm](http://github.com/flussonic/epm), fixed several issues with epm under Centos systems and embedded it.  The
easiest way to start using this plugin is to install the corresponding
[template](http://github.com/openx/rebar3_service_rpm_template), and use
that as a basis for an erlang service.

Conventions
-----------
When building a release and using overlays the resulting release directory
layout is used to build rpms.  The following conventions will be applied

1. the release itself will be install in /usr/lib64/release_name/ unless the prefix is overridden.
2. the contents of the directory 'slash' will be copied into '/' of the package.  'slash' should exist at the top level of the release.
3. if the directory 'slash/internal' exists the following scripts will be looked for and added to the rpm (but will not exist as files in the final rpm)
   * pre.sh - run at the pre-install script of rpm installation
   * post.sh - run at the post-install script of rpm installation
   * preun.sh - run before uninstalling or upgrading
   * postun.sh - run after uninstalling or upgrading
